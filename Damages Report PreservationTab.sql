WITH RelevantLoans AS (
    SELECT  
	oqw.LoanNumber,
	oqw.OrderDetailID,
	oqw.orderid,
	oqw.CustomerProduct
    FROM OrderDamagesTracking od
    JOIN OQW oqw ON oqw.OrderDetailID = od.OrderDetailID
    WHERE CAST(od.DamageReportedDate AS DATE) >= CAST(GETDATE()-1 AS DATE)
	and CustomerAcct = 'MCO-7001'
	and businessproductclassid = 39 
	group by orderid, LoanNumber, oqw.OrderDetailID, CustomerProduct
	--Preservation Only query
	-- REMINDER TO SWAP FOR CFB-7001 WHEN GOING TO PRODUCTION
),

FilteredADW AS (
    SELECT 
        adw.OrderId,
        Max(adw.rulevalue) As rulevalue
	     --ROW_NUMBER() OVER (PARTITION BY adw.OrderDetailID ORDER BY (SELECT NULL)) AS rn
    FROM ADW adw WITH (NOLOCK)
	JOIN OQW oqw3 ON oqw3.OrderID = adw.OrderId
    WHERE adw.OrderDetailElementName = 'Most Recent Occupancy Status'
	AND oqw3.CustomerAcct = 'MCO-7001'
	AND oqw3.businessproductid= 515
	GROUP BY adw.OrderId, adw.RuleValue
),
Investor AS (
		Select 
			lad.TextValue, 
			lad.OrderID,
			ROW_NUMBER() OVER (PARTITION BY lad.orderid ORDER BY (SELECT NULL)) AS rn1
			FROM LAD lad  WITH (NOLOCK)
			JOIN RelevantLoans rl4 on rl4.OrderID = lad.OrderID
			WHERE LoanElementID = 1
			GROUP BY lad.TextValue,lad.OrderID
),
BorrowerName AS (
			Select 
			oc.txt_last_name,
			oc.order_id,
			oc.order_detail_ID,
			ROW_NUMBER() OVER (PARTITION BY oc.order_id ORDER BY (SELECT NULL)) AS rn2
			FROM OC oc  WITH (NOLOCK)
			JOIN OQW oqw ON oqw.OrderID = oc.Order_ID
			where oqw.BusinessProductID = 515

)


-- Step 4: Final query
SELECT 
od.Orderdamagesid,
od.DamageType,
oqw.Orderdetailid,
oqw.orderid,
	ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS [Count],
	oqw.LoanNumber AS [Loan Number],
	oqw.OrderNumber AS [Work Order Number],
	fadw.rulevalue AS [Occupancy],
	'' AS [Exterior Condition],
	i.TextValue AS [Loan Investor Type],
	oqw.LoanType AS [Loan Type],
	oqw.CustomerProduct AS [Work Type],
	oc.txt_last_name AS [Borrower Name],
	oqw.StreetAddress AS [Address],
    oqw.City,
    oqw.State,
    oqw.Zip,
	od.DamageReportedDate AS [Received Date],
	od.DamageReportedDate AS [Completed Date],


	CASE 
    WHEN FORMAT(oqw.LastBilled, 'dddd') = 'Friday' THEN DATEADD(DAY, 3, oqw.LastBilled)
    WHEN FORMAT(oqw.LastBilled, 'dddd') = 'Saturday' THEN DATEADD(DAY, 2, oqw.LastBilled)
    WHEN FORMAT(oqw.LastBilled, 'dddd') = 'Sunday' THEN DATEADD(DAY, 1, oqw.LastBilled)
    ELSE DATEADD(DAY, 1, oqw.LastBilled)
	END AS [Invoice Date],  --Next business day after Last Billed Date bc we dont know when stuff is actually invoiced,
	od.DamageAmount AS [Eye Ball Damages Estimate],
	
	CASE
        WHEN DamageType = 'MildewMold' THEN 'Yes'
        --WHEN DamageType = 'Furnace Damage' THEN 'Yes'
		ELSE 'No'
    END AS Mold,

	CASE
       WHEN DamageType = 'Broken Windows' THEN 'Yes'
       ELSE 'No'
    END AS [Broken Windows],

	'' AS [Broken Windows Comments],

	CASE
        WHEN DamageType = 'Roof' THEN 'Yes'
        ELSE 'No'
    END AS [Roof Leak],

	CASE
		WHEN DamageType = 'Roof' THEN
	'Source: '+ od.DamageSource + 'Location: '+ od.DamageLocation 
	ELSE ''
	END AS [Roof Leak Comments],

	CASE
        WHEN DamageType = 'Vandalism' THEN 'Yes'
		WHEN DamageType = 'Graffiti' THEN 'Yes'
        ELSE 'No'
    END AS Vandalism,

	CASE
        WHEN DamageType = 'Vandalism' THEN 'Source: '+ od.DamageSource + ' Location: '+ od.DamageLocation 
		WHEN DamageType = 'Graffiti' THEN 'Source: '+ od.DamageSource + ' Location: '+ od.DamageLocation 
	ELSE ''
	END AS [Vandalism Comments],

    CASE
        WHEN DamageType = 'Fire' THEN 'Yes'
		WHEN DamageType = 'Smoke' THEN 'Yes'
        ELSE 'No'
    END AS [Fire Damage],

	 CASE
        WHEN DamageType = 'Fire' THEN 'Source: '+ od.DamageSource + ' Location: '+ od.DamageLocation
		WHEN DamageType = 'Smoke' THEN 'Source: '+ od.DamageSource + ' Location: '+ od.DamageLocation
		ELSE ''
	END AS [Fire Damage Comments],

	CASE
        WHEN DamageType = 'Flood' THEN 'Yes'
		WHEN DamageType = 'Sump Pump' THEN 'Yes'
		WHEN DamageType = 'Water' THEN 'Yes'
		WHEN DamageType = 'Damaged Pipes' THEN 'Yes'
        ELSE 'No'
		END AS [Water Damage],

	CASE
        WHEN DamageType = 'Flood' THEN 'Source: '+ od.DamageSource + ' Location: '+ od.DamageLocation
		WHEN DamageType = 'Sump Pump' THEN 'Source: '+ od.DamageSource + ' Location: '+ od.DamageLocation
		WHEN DamageType = 'Water' THEN 'Source: '+ od.DamageSource + ' Location: '+ od.DamageLocation
		WHEN DamageType = 'Damaged Pipes' THEN 'Source: '+ od.DamageSource + ' Location: '+ od.DamageLocation
        ELSE ''
    END AS [Water Damage Comments],

	'' AS [Pipes Burst],

	'' AS [Pipes Burst Comments],

	CASE
        WHEN DamageType = 'Freeze' THEN 'Yes'
        ELSE 'No'
    END AS [Freeze Damage],

	CASE
        WHEN DamageType = 'Freeze' THEN 'Source: '+ od.DamageSource + ' Location: '+ od.DamageLocation
        ELSE ''
    END AS [Freeze Damage Comments],
	
	'' AS [Exterior General Condition],
	'' AS [Interior General Condition],
	'' AS [Exterior Debris Comments],
	'' AS [Interior Debris Comments],
	'' AS [Removed Health Hazard],
	'' AS [Health Hazard Comments],
	CASE
		WHEN DamageType NOT IN ('MildewMold','Broken Windows','Roof','Vandalism','Graffiti','Fire','Smoke','Flood','Sump Pump','Water','Damaged Pipes','Freeze') 
		THEN 'Damage Type: '+ od.Damagetype + ' Source: '+ od.DamageSource + ' Location: '+ od.DamageLocation
		ELSE 'Source: '+ od.DamageSource + 'Location: '+ od.DamageLocation
	END AS [Comments from rep]

FROM OD od
JOIN OQW oqw ON oqw.OrderDetailID = od.OrderDetailID
JOIN RelevantLoans rl ON rl.LoanNumber = oqw.LoanNumber
--LEFT JOIN ParentOrders po ON po.LoanNumber = oqw.LoanNumber
LEFT JOIN FilteredADW fadw ON fadw.OrderId = oqw.OrderID --where oqw.BusinessProductID =515 
LEFT JOIN Investor i ON oqw.OrderID = i.OrderID and i.rn1=1
LEFT JOIN BorrowerName oc ON oqw.OrderID = oc.Order_ID and oc.rn2=1

WHERE CAST(od.DamageReportedDate AS DATE) >= CAST(GETDATE() -1 AS DATE)
AND oqw.CustomerAcct = 'MCO-7001'
AND oqw.BusinessProductClassid = 39
