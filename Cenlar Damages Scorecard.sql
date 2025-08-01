WITH RelevantLoans AS (
    SELECT DISTINCT 
	oqw.LoanNumber, 
	oqw.StreetAddress,
	oqw.City,
	oqw.State,
	oqw.Zip,
	oqw.CustomerProduct,
	oqw.OrderID, 
	oqw.OrderDetailID, 
	oqw.Ordernumber, 
	od.DamageReportedDate, 
	od.DamageType, 
	od.OrderDamagesID, 
	oqw.LoanType,
	oqw.LastBilled
FROM OD od
JOIN oqw oqw ON oqw.OrderDetailID = od.OrderDetailID
WHERE CAST(od.DamageReportedDate AS DATE) >= DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()) - 1, 0)
	AND CAST(od.DamageReportedDate AS DATE) < DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)
	and CustomerAcct = 'MCO-7001'
	-- REMINDER TO SWAP FOR CFB-7001 WHEN GOING TO PRODUCTION
),
  
-- Step 2: Get occupancy for work orders 
Occupancy AS (
    SELECT 
        adw.OrderDetailID,
        MAX(adw.rulevalue) AS rulevalue  -- Or MIN, or STRING_AGG depending on needs
    FROM adw adw WITH (NOLOCK)
    JOIN RelevantLoans rn ON rn.OrderDetailID = adw.OrderDetailID
    WHERE adw.OrderDetailElementName ='PPW occupancy status'
    GROUP BY adw.OrderDetailID
),
ServiceComplete AS (
    SELECT 
        adw.OrderDetailID,
        MAX(adw.rulevalue) AS rulevalue  -- Or MIN, or STRING_AGG depending on needs
    FROM adw adw WITH (NOLOCK)
    JOIN RelevantLoans rn ON rn.OrderDetailID = adw.OrderDetailID
    WHERE adw.OrderDetailElementName ='service complete date'
    GROUP BY adw.OrderDetailID
),

--Loan Investor Type write subquery to loanadditionaldata
Investor AS (
			Select 
			lad.TextValue, 
			lad.OrderID
			FROM LAD lad  WITH (NOLOCK)
			JOIN RelevantLoans rn2 on rn2.OrderID= lad.OrderID
			WHERE LoanElementID = 1
			GROUP BY lad.TextValue,lad.OrderID
)
SELECT 
    rn.LoanNumber,
	rn.LoanType,
    rn.OrderID,
    rn.OrderDetailID,
	rn.OrderNumber,
	rn.DamageType,
	rn.DamageReportedDate,
	rn.OrderDamagesID,
    i.TextValue AS InvestorType,
	rn.CustomerProduct AS [Work Type],
    rn.StreetAddress AS [Address],
	rn.City,
	rn.State,
	rn.Zip AS [Zip Code],
    occ.rulevalue AS OccupancyStatus,
	scd.rulevalue AS [Inspected Date],
	--CAST(GETDATE() -3 AS DATE) AS [Inspected Date],

CASE 
    WHEN FORMAT(rn.LastBilled, 'dddd') = 'Friday' THEN DATEADD(DAY, 3, rn.LastBilled)
    WHEN FORMAT(rn.LastBilled, 'dddd') = 'Saturday' THEN DATEADD(DAY, 2, rn.LastBilled)
    WHEN FORMAT(rn.LastBilled, 'dddd') = 'Sunday' THEN DATEADD(DAY, 1, rn.LastBilled)
    ELSE DATEADD(DAY, 1, rn.LastBilled)
END AS [Invoice Date],  --Next business day after Last Billed Date bc we dont know when stuff is actually invoiced
	CASE 
    WHEN FORMAT(rn.LastBilled, 'dddd') = 'Friday' THEN DATEADD(DAY, 3, rn.LastBilled)
    WHEN FORMAT(rn.LastBilled, 'dddd') = 'Saturday' THEN DATEADD(DAY, 2, rn.LastBilled)
    WHEN FORMAT(rn.LastBilled, 'dddd') = 'Sunday' THEN DATEADD(DAY, 1, rn.LastBilled)
    ELSE DATEADD(DAY, 1, rn.LastBilled)
END AS [Notification Date],  --Next business day after Last Billed Date bc this will be on the automated daily damage reports **** maybe to handle the nulls when people report odireclty on n CUstomerProduct = PropertyPreservation to fill with Damage Reported date +1 

(
    DATEDIFF(DAY, rn.LastBilled, 
        CASE 
            WHEN FORMAT(rn.LastBilled, 'dddd') = 'Friday' THEN DATEADD(DAY, 3, rn.LastBilled)
            WHEN FORMAT(rn.LastBilled, 'dddd') = 'Saturday' THEN DATEADD(DAY, 2, rn.LastBilled)
            WHEN FORMAT(rn.LastBilled, 'dddd') = 'Sunday' THEN DATEADD(DAY, 1, rn.LastBilled)
            ELSE DATEADD(DAY, 1, rn.LastBilled)
        END
    )
    - 2 * DATEDIFF(WEEK, rn.LastBilled,
        CASE 
            WHEN FORMAT(rn.LastBilled, 'dddd') = 'Friday' THEN DATEADD(DAY, 3, rn.LastBilled)
            WHEN FORMAT(rn.LastBilled, 'dddd') = 'Saturday' THEN DATEADD(DAY, 2, rn.LastBilled)
            WHEN FORMAT(rn.LastBilled, 'dddd') = 'Sunday' THEN DATEADD(DAY, 1, rn.LastBilled)
            ELSE DATEADD(DAY, 1, rn.LastBilled)
        END
    )
) AS [Days],
	'' AS Comments
		   	 
FROM RelevantLoans rn
LEFT JOIN Occupancy occ ON rn.OrderDetailID = occ.OrderDetailID
LEFT JOIN ServiceComplete scd ON rn.OrderDetailID = scd.OrderDetailID
LEFT JOIN Investor i ON rn.OrderID = i.OrderID

