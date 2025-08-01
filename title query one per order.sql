WITH EventTimes AS (
    SELECT
        owf.orderdetailid,
        owf.businesseventid,
        owf.enteredevent,
        owf.actingemployeeid,
        owf.actingemployeedisplayname,
        owf.customerproduct
    FROM OWF owf
    WHERE owf.businessproductclassid = 61
      AND owf.businesseventid IN (1136, 14)
      AND owf.enteredevent >= DATEADD(MONTH, -6, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1))
      AND owf.enteredevent < DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)
),
All1136 AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY orderdetailid ORDER BY enteredevent) AS rn
    FROM EventTimes
    WHERE businesseventid = 1136
),
PairedEvents AS (
    SELECT
        a.orderdetailid,
        a.enteredevent AS first_1136_time,
        (
            SELECT MIN(e.enteredevent)
            FROM EventTimes e
            WHERE e.orderdetailid = a.orderdetailid
              AND e.businesseventid = 1136
              AND e.enteredevent > a.enteredevent
        ) AS next_1136_time
    FROM All1136 a
),
ReviewCandidates AS (
    SELECT
        p.orderdetailid,
        p.first_1136_time,
        p.next_1136_time,
        e.enteredevent AS review_time,
        e.actingemployeeid,
        e.actingemployeedisplayname,
        e.customerproduct,
        ROW_NUMBER() OVER (
            PARTITION BY p.orderdetailid, p.first_1136_time
            ORDER BY e.enteredevent
        ) AS rn
    FROM PairedEvents p
    JOIN EventTimes e
      ON p.orderdetailid = e.orderdetailid
     AND e.businesseventid = 14
     AND e.enteredevent > p.first_1136_time
     AND (p.next_1136_time IS NULL OR e.enteredevent < p.next_1136_time)
),
Final AS (
    SELECT *
    FROM ReviewCandidates
    WHERE rn = 1
)
SELECT
    orderdetailid AS [Order Detail ID],
    first_1136_time AS [Typing Outsourced],
    review_time AS [Review Report],
    ROUND(CAST(DATEDIFF(SECOND, first_1136_time, review_time) AS FLOAT) / 3600, 2) AS [Hours in Queue],
    actingemployeeid AS [Employee ID],
    actingemployeedisplayname [Employee Name],
    customerproduct AS [Customer Product],
    CASE 
        WHEN CAST(CONVERT(TIME, review_time) AS TIME) BETWEEN '08:00:00' AND '16:59:59' THEN 'No'
        ELSE 'Yes'
    END AS [Overnight Review],
CASE 
    -- Submitted before 12 PM and reviewed by 5 PM same day
    WHEN 
        CAST(first_1136_time AS TIME) < '12:00:00' AND 
        CAST(review_time AS DATETIME) <= DATEADD(HOUR, 17, CAST(CAST(first_1136_time AS DATE) AS DATETIME))
    THEN 1

    -- Submitted at or after 12 PM and reviewed by 8 AM next day
    WHEN 
        CAST(first_1136_time AS TIME) >= '12:00:00' AND 
        CAST(review_time AS DATETIME) <= DATEADD(HOUR, 8, DATEADD(DAY, 1, CAST(CAST(first_1136_time AS DATE) AS DATETIME)))
    THEN 1

    ELSE 0
END AS [Done On Time]



FROM Final
WHERE customerproduct NOT IN (
    'Full Title Search',
    'Internal Title Update',
    'Legal and Vesting Report',
    'Legal and Vesting with Mortgages',
    'Title Update'
)
--AND OrderDetailID = 103092007
ORDER BY [Hours in Queue] DESC;
                               