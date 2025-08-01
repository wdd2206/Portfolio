-- Step 1: Identify qualifying OrderDetailIDs
WITH FirstReviewOrAddendum AS (
    SELECT
        OrderDetailID,
        MIN(EnteredEvent) AS FirstEventDate
    FROM [OWP]
    WHERE BusinessEventID = 14
      AND ActingEmployeeID <> 20137
      AND EnteredEvent >= DATEADD(MONTH, -6, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1))
      AND EnteredEvent < DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)
    GROUP BY OrderDetailID
),

-- Step 2: Filter and prepare event data
FilteredEvents AS (
    SELECT *
    FROM [OWP]
    WHERE BusinessEventID IN (7,11,12,14,32,34,35,508,1131)
      AND EnteredEvent >= DATEADD(MONTH, -6, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1))
      AND EnteredEvent < DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)
      AND BusinessProductClassID = 22
      AND CustomerAccount NOT LIKE '%SHA%'
      AND OrderDetailID IN (SELECT OrderDetailID FROM FirstReviewOrAddendum)
),

-- Step 3: Assign row numbers to events for pairing
RankedEvents AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY OrderDetailID, ActingEmployeeID ORDER BY EnteredEvent) AS rn
    FROM FilteredEvents
),

-- Step 4: Pair each 14 with the next 11,12,508,1131
EventPairs AS (
    SELECT 
        e14.OrderDetailID,
        e14.ActingEmployeeID,
        e14.EnteredEvent AS StartEvent,
        eNext.EnteredEvent AS EndEvent,
        DATEDIFF(SECOND, e14.EnteredEvent, eNext.EnteredEvent) AS SecondsBetweenEvents
    FROM RankedEvents e14
    JOIN RankedEvents eNext
      ON e14.OrderDetailID = eNext.OrderDetailID
     AND e14.ActingEmployeeID = eNext.ActingEmployeeID
     AND eNext.rn = e14.rn + 1
     AND e14.BusinessEventID = 14
     AND eNext.BusinessEventID IN (11, 12, 508, 1131)
),

-- Step 5: Aggregate durations
SummedDurations AS (
    SELECT 
        OrderDetailID,
        ActingEmployeeID,
        SUM(SecondsBetweenEvents) AS TotalSecondsBetweenEvents
    FROM EventPairs
    GROUP BY OrderDetailID, ActingEmployeeID
),

-- Step 6: Add event sequence info
EventSequence AS (
    SELECT *,
           LEAD(BusinessEventID) OVER (PARTITION BY OrderDetailID ORDER BY EnteredEvent) AS NextBusinessEventID,
           LAG(BusinessEventID) OVER (PARTITION BY OrderDetailID ORDER BY EnteredEvent) AS PrevBusinessEventID,
           LEAD(ActingEmployeeID) OVER (PARTITION BY OrderDetailID ORDER BY EnteredEvent) AS NextActingEmployeeID,
           LAG(ActingEmployeeID) OVER (PARTITION BY OrderDetailID ORDER BY EnteredEvent) AS PrevActingEmployeeID,
           ROW_NUMBER() OVER (PARTITION BY OrderDetailID ORDER BY EnteredEvent) AS RowNum
    FROM FilteredEvents
),

-- Step 7: Identify valid 14→12→32→34 sequences
ValidSequences AS (
    SELECT OrderDetailID, EnteredEvent AS Event14Time
    FROM (
        SELECT 
            OrderDetailID,
            EnteredEvent,
            BusinessEventID,
            LEAD(BusinessEventID, 1) OVER (PARTITION BY OrderDetailID ORDER BY EnteredEvent) AS BE_2,
            LEAD(BusinessEventID, 2) OVER (PARTITION BY OrderDetailID ORDER BY EnteredEvent) AS BE_3,
            LEAD(BusinessEventID, 3) OVER (PARTITION BY OrderDetailID ORDER BY EnteredEvent) AS BE_4
        FROM FilteredEvents
    ) AS Seq
    WHERE BusinessEventID = 14 AND BE_2 = 12 AND BE_3 = 32 AND BE_4 = 34
),

-- Step 8: Classify ReviewType per event
ReviewTypes AS (
    SELECT 
        es.*,
        CASE
            WHEN es.BusinessEventID = 14 THEN
                CASE 
                    WHEN es.RowNum = 1 THEN 'First Review'
                    WHEN es.PrevBusinessEventID = 35 THEN 'Addendum Review'
                    WHEN es.PrevBusinessEventID IN (11,12,15,1131) THEN 'Re-Review'
                    ELSE 'Other'
                END
            ELSE NULL
        END AS ReviewType
    FROM EventSequence es
),

-- Step 9: Calculate TotalOrderCost
TotalOrderCostCalc AS (
    SELECT 
        OrderDetailID,
        SUM(
            CASE 
                WHEN ReviewType = 'First Review' THEN 2
                WHEN ReviewType = 'Addendum Review' THEN 2
                WHEN ReviewType = 'Re-Review' THEN 0.5
                ELSE 0
            END
        ) AS TotalOrderCost
    FROM ReviewTypes
    WHERE BusinessEventID = 14
    GROUP BY OrderDetailID
)

-- Step 10: Final selection
SELECT 
    es.[ActingEmployeeID],
    es.[ActingEmployeeDisplayName],
    CASE  
        WHEN es.ActingEmployeeDisplayName LIKE '%-ASC%' THEN 'Ascendum'
        ELSE 'SSPS'
    END AS [Employee Location],
    CAST(es.EnteredEvent AS DATE) AS Date,
    es.[OrderDetailID],
    oqw.OrderID,  -- Re-added OrderID from OrderQueueWarehouse
    es.[EnteredEvent],
    es.[ExitedEvent],
    DATEDIFF(SECOND, es.EnteredEvent, es.ExitedEvent) AS [Seconds On Task],
    DATEDIFF(SECOND, es.EnteredEvent, es.ExitedEvent) / 60.0 AS [Minutes On Task],
    toc.TotalOrderCost,
    sd.TotalSecondsBetweenEvents / 60.0 AS [Total Minutes All Reviews],
    DATEDIFF(SECOND, es.EnteredEvent, es.ExitedEvent) / 3600.0 AS [Hours On Task],
    es.[BusinessEventID],
    es.[BusinessEvent],
    CASE 
        WHEN vs.OrderDetailID IS NOT NULL 
             AND es.BusinessEventID = 14 
             AND es.EnteredEvent = vs.Event14Time
        THEN 1 
        ELSE NULL 
    END AS AddendumFlag,
    CASE 
        WHEN es.BusinessEventID = 14 AND es.NextBusinessEventID IN (11,1131) THEN 'Rejected'
        WHEN es.BusinessEventID = 14 AND es.NextBusinessEventID IN (12,32,508) THEN 'Accepted'
        WHEN es.BusinessEventID = 14 AND es.NextBusinessEventID = 7 THEN 'Cancelled'
        ELSE NULL
    END AS [Status],
    es.ReviewType,
    CASE
        WHEN es.BusinessEventID = 14 
             AND es.NextBusinessEventID = 14 
             AND es.ActingEmployeeID <> es.NextActingEmployeeID THEN 'Escalated'
        WHEN es.BusinessEventID = 14 
             AND es.NextBusinessEventID = 14 
             AND es.ActingEmployeeID = es.NextActingEmployeeID THEN 'Exception'
        ELSE ''
    END AS Escalated,
    es.[OrderDetailEventID],
    es.[BusinessStatusID],
    es.[BusinessStatus],
    es.[CustomerProductID],
    es.[CustomerProduct],
    es.[CustomerAccount],
    es.[Customer],
    es.[BusinessProductID],
    es.[BusinessProduct],
    es.[BusinessProductClassID],
    es.[BusinessProductClass],
    sd.TotalSecondsBetweenEvents
FROM ReviewTypes es
LEFT JOIN TotalOrderCostCalc toc
    ON es.OrderDetailID = toc.OrderDetailID
LEFT JOIN SummedDurations sd
    ON es.OrderDetailID = sd.OrderDetailID
    AND es.ActingEmployeeID = sd.ActingEmployeeID
LEFT JOIN ValidSequences vs
    ON es.OrderDetailID = vs.OrderDetailID
    AND es.EnteredEvent = vs.Event14Time
LEFT JOIN [oqw] oqw
    ON es.OrderDetailID = oqw.OrderDetailID

