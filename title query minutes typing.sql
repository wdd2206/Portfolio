WITH TypingEmployees AS (
    SELECT 
        employee_id,
        txt_display_name,
        CASE 
            WHEN txt_last_name LIKE '%-IND' THEN 'Indecomm'
            WHEN txt_last_name LIKE '%-SIT' THEN 'SitusAMC'
			WHEN txt_last_name LIKE '%-ASC' THEN 'Ascendum'
		ELSE txt_employee_title
        END AS Outsourcer
    FROM Employee
   
),

FormDataWithOutsourcer AS (
    SELECT 
        U.orderdetailid,
        te.Outsourcer,
        te.employee_id AS ActingUserID,
        te.txt_display_name,
        U.DurationSeconds, 
        U.ActivityID,
        U.Occurred
    FROM UAL U
    INNER JOIN TypingEmployees te
        ON U.ActingEmployeeID = te.employee_id
    WHERE U.ApplicationID = 24
),

Owf AS (
    SELECT
        owf.actingemployeeid,
        owf.orderdetailid,
        owf.customerproduct,
        owf.businesseventid,
        owf.enteredevent,
        owf.businessproductclassid,
        ROW_NUMBER() OVER (
            PARTITION BY owf.orderdetailid
            ORDER BY owf.enteredevent ASC
        ) AS rn
    FROM OWF owf
    WHERE owf.businesseventid = 14
),

FilteredOwf AS (
    SELECT 
        actingemployeeid,
        orderdetailid,
        customerproduct,
        businessproductclassid
    FROM Owf
    WHERE rn = 1
),

RankedActivities AS (
    SELECT 
        u.OrderDetailID,
        u.ActingEmployeeID,
        u.Occurred,
        u.DurationSeconds,
        u.ActivityID,
        ROW_NUMBER() OVER (
            PARTITION BY u.OrderDetailID, u.ActingEmployeeID
            ORDER BY 
                CASE 
                    WHEN u.ActivityID = 17 THEN 1
                    WHEN u.ActivityID = 16 THEN 2
                    WHEN u.ActivityID = 15 THEN 3
                    ELSE 4
                END,
                u.Occurred DESC
        ) AS rn
    FROM UAL u
    WHERE u.ActivityID IN (4, 5, 15, 16, 17)
      AND u.OrderDetailID IS NOT NULL
)

SELECT
    ra.OrderDetailID,
    ra.ActingEmployeeID,
    te.txt_display_name,
	te.Outsourcer,
    fowf.customerproduct,
    ra.Occurred,
    ROUND(ra.DurationSeconds / 60.0, 2) AS [Minutes Typing],
    ra.ActivityID,
    ra.rn
FROM RankedActivities ra
INNER JOIN FilteredOwf fowf
    ON ra.OrderDetailID = fowf.orderdetailid
   AND fowf.businessproductclassid = 61
LEFT JOIN TypingEmployees te
    ON ra.ActingEmployeeID = te.employee_id
WHERE ra.rn = 1
  AND ra.ActivityID IN (15, 16, 17)
  --AND ra.OrderDetailID = 109016385
  AND Outsourcer IN ('SitusAmc','Ascendum','Indecomm')

  --AND ra.Occurred >= DATEADD(MONTH, -6, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1))
  --AND ra.Occurred < DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)

ORDER BY Occurred DESC;
