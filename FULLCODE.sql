-- GETTING SENSE DATA
SELECT *
FROM [AdventureWorks2022].[dbo].[Online Retail]

-- Invoices which has the UnitPrice = 0
SELECT *
FROM [AdventureWorks2022].[dbo].[Online Retail]
WHERE UnitPrice = 0 

-- Select invoice with negative quantity number
SELECT *
FROM [AdventureWorks2022].[dbo].[Online Retail]
WHERE quantity < 0

-- Understand stock code and letter "C" before the InvoiceNo having negative quantity
SELECT *
FROM [AdventureWorks2022].[dbo].[Online Retail]
WHERE PATINDEX('%[^A-Za-z]%', [StockCode]) = 0 AND quantity <= 0
ORDER BY InvoiceNo
/* I realized some negative quantity in the Invoiceno bginning with letter 'C', which is how the company fixes cancelaion in the 
order record by subtracting with the same unit numbers. However, some of these are considered as "Cost" (discount, fee, bank charge, samples,..) */

-- Select invoices which has CustomerID is NULL
SELECT *
FROM [AdventureWorks2022].[dbo].[Online Retail]
WHERE CustomerID IS NULL

-- Select invoices which has Description  is NULL
SELECT *
FROM [AdventureWorks2022].[dbo].[Online Retail]
WHERE Description  IS NULL

-- DATA CLEANING
WITH retail AS (
SELECT *
FROM [AdventureWorks2022].[dbo].[Online Retail]
WHERE CustomerID ! =''
 ),
 
 quantity_unit_price AS (
SELECT *
FROM retail
WHERE Quantity > 0 AND UnitPrice > 0
),

dup_check AS (
SELECT *, 
	ROW_NUMBER() OVER (PARTITION BY InvoiceNo, StockCode, CAST(Quantity AS numeric) ORDER BY CAST(InvoiceDate AS DATE)) AS dup
FROM quantity_unit_price
)

SELECT 
	* 
INTO #online_retail_clean
FROM dup_check
WHERE dup = 1;

SELECT * FROM #online_retail_clean;


-- EXPLORATION ANALYSIS
-- Total revenue by month
SELECT DATEADD(MONTH, DATEDIFF(MONTH, 0, InvoiceDate), 0) AS Sales_Month, 
       SUM(UnitPrice*Quantity) as Revenue
FROM #online_retail_clean
GROUP BY DATEADD(MONTH, DATEDIFF(MONTH, 0, InvoiceDate), 0)
ORDER BY Sales_Month;

-- Total revenue by country
SELECT Country,
       ROUND(SUM(unitprice*quantity),0) as Revenue
FROM #online_retail_clean
GROUP BY Country
ORDER BY 2 desc;

-- How many orders does customer have
SELECT CustomerId, 
     COUNT(DISTINCT InvoiceNo) as orders_per_customer
FROM #online_retail_clean
GROUP BY CustomerId
ORDER BY 2 desc;

-- Which customer has single purchase from company
SELECT CustomerId, orders_per_customer, unique_number_product
FROM (
    SELECT 
        CustomerId,
        COUNT(DISTINCT InvoiceNo) as orders_per_customer,
        COUNT(DISTINCT Description) as unique_number_product
    FROM #online_retail_clean
    GROUP BY CustomerId
) AS Subquery
WHERE orders_per_customer = 1
ORDER BY 3 DESC;

-- Average interval between each order   (I only got one date for orders belonging to one customer id which happened many times on the same date to calculate)
SELECT CustomerId, 
      AVG(Interval) AS avg_interval_btw_each_order,
      COUNT(Interval) AS number_interval
FROM
(
    SELECT DISTINCT customerid,  
     invoicedate, 
     LEAD(invoicedate) over (partition by customerid order by invoicedate) as next_order_date,
     COALESCE(DATEDIFF(day, invoicedate, LEAD(invoicedate) over (partition by customerid order by invoicedate)),0) AS Interval
    FROM #online_retail_clean
) a
WHERE interval != 0
GROUP BY CustomerId

-- Best selling product
SELECT Description, 
     SUM(Quantity) as total_quantity_per_product, 
     ROUND(SUM(Quantity * UnitPrice), 0) as sales_per_product, 
     COUNT(DISTINCT InvoiceNo) as distinct_product_ordes
FROM #online_retail_clean
GROUP BY Description
ORDER BY 2 DESC;

-- RFM ANALYSIS
WITH My_Data AS (
    SELECT
         CustomerID,
         InvoiceNo,
         SUM(Quantity * UnitPrice) AS Sales,
         InvoiceDate
    FROM #online_retail_clean
    GROUP BY CustomerID, InvoiceNo, InvoiceDate
),

RFM_Base AS (
    SELECT 
         t1.CustomerID,
         DATEDIFF(day, (SELECT MAX(InvoiceDate) FROM My_Data WHERE CustomerID = t1.CustomerID), 
                        (SELECT MAX(InvoiceDate) FROM My_Data)) AS Recency,
         COUNT(t1.InvoiceNo) AS Frequency,
         SUM(t1.Sales) AS Monetary
    FROM My_Data t1
    GROUP BY t1.CustomerID
),

RFM_Score AS (
    SELECT *,
        NTILE(5) OVER (ORDER BY Recency DESC) AS R_Score,
        NTILE(5) OVER (ORDER BY Frequency ASC) AS F_Score,
        NTILE(5) OVER (ORDER BY Monetary ASC) AS M_Score
    FROM RFM_Base
),

RFM_Final AS (
    SELECT *,
        CONCAT(R_Score, F_Score, M_Score) AS RFM_Overall
    FROM RFM_Score
)

SELECT f.*, s.Segment
FROM RFM_Final f
JOIN [AdventureWorks2022].[dbo].[segment scores] s ON f.RFM_Overall = s.Scores;

-- COHORT ANALYSIS
-- Create cohort temp table which contains unique customer ID and first purchase date
SELECT
	CustomerID,
	min(CAST( InvoiceDate AS Date)) AS first_purchase_date,
	DATEFROMPARTS(year(min(CAST( InvoiceDate AS Date))),month(min(CAST( InvoiceDate AS Date))),1) AS Cohort_Date
INTO #cohort
FROM #online_retail_clean
GROUP BY CustomerID;

--Calculate Cohort Index
WITH CTE AS(
SELECT
	o.*,
	c.Cohort_Date,
	year(CAST(o.InvoiceDate AS Date)) AS invoice_year,
	month(CAST(o.InvoiceDate AS Date)) AS invoice_month,
	year(CAST(c.Cohort_Date AS Date)) AS cohort_year,
	month(CAST(c.Cohort_Date AS Date)) AS cohort_month
FROM #online_retail_clean AS o
LEFT JOIN #cohort AS c
ON o.CustomerID=c.CustomerID
)

,Cte2 AS (
--Derive the year_diff and month_diff columns
SELECT 
	CTE.*,
	year_diff=invoice_year-cohort_year,
	month_diff=invoice_month-cohort_month
FROM CTE 
)
--Calculate cohort index
SELECT 
	cte2.*,
	year_diff*12+month_diff+1 AS cohort_index
--place CTE stack into a temp table #cohorts_retention
INTO #cohorts_retention
FROM cte2

--Select all columns from cohorts_retention temp table
SELECT * FROM #cohorts_retention;

SELECT DISTINCT customerID,
		Cohort_Date,
		cohort_index
FROM #cohorts_retention
ORDER BY CustomerID,cohort_index;


--Retrieve the unique customerID, cohort date and cohort index from #cohorts_retention
--Pass the above query into the PIVOT operator
--Pass the query into a temp table #cohort_pivot
SELECT
	*
INTO #cohort_pivot
FROM (
	SELECT DISTINCT 
		CustomerID,
		Cohort_Date,
		cohort_index
	FROM #cohorts_retention
	)tbl
PIVOT(
COUNT(CustomerID)
FOR Cohort_Index In ([1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11],[12],[13])

)AS PIVOT_TABLE
ORDER BY Cohort_Date
go


--Cohort Retention Rate
SELECT 
	Cohort_Date, 
	1.0*[1]/[1]*100 AS [1],
	1.0*[2]/[1]*100 AS [2],
	1.0*[3]/[1]*100 AS [3],
	1.0*[4]/[1]*100 AS [4],
	1.0*[5]/[1]*100 AS [5],
	1.0*[6]/[1]*100 AS [6],
	1.0*[7]/[1]*100 AS [7],
	1.0*[8]/[1]*100 AS [8],
	1.0*[9]/[1]*100 AS [9],
	1.0*[10]/[1]*100 AS [10],
	1.0*[11]/[1]*100 AS [11],
	1.0*[13]/[1]*100 AS [12],
	1.0*[13]/[1]*100 AS [13]
FROM #cohort_pivot
ORDER BY Cohort_Date;

--there are 13 distinct values in the cohort_index colunm
--SELECT DISTINCT
--		cohort_index
--	FROM #cohorts_retention

SELECT * FROM #cohort_pivot ORDER BY Cohort_Date

-- BASKET ANALYSIS 
-- Create CTE (Order_List) identifies customers who placed only one order (orders_per_customer = 1) but purchased at least three distinct product
 WITH Order_List AS 
(
SELECT CustomerId, orders_per_customer, unique_number_product
FROM (
    SELECT 
        CustomerId,
        COUNT(DISTINCT invoiceno) as orders_per_customer,
        COUNT(DISTINCT description) as unique_number_product
    FROM #online_retail_clean
    GROUP BY Customerid
    HAVING COUNT(DISTINCT description) >= 3
) AS Subquery
WHERE orders_per_customer = 1 
)
-- Create CTE (Infor) retrieves product descriptions for each customer found in the Order_List CTE.
, Infor AS 
(
SELECT Order_List.customerid, FIS.description
FROM Order_List
JOIN #online_retail_clean AS FIS ON Order_List.customerid = FIS.customerid
)
--Identifies product triplets frequently bought together by customers in their single order.
SELECT TOP 10000
     Infor1.description AS Product1,
     Infor2.description AS Product2,
     Infor3.description AS Product3,
     COUNT(*) AS Frequency
FROM Infor AS Infor1
JOIN Infor AS Infor2 ON Infor1.customerid = Infor2.customerid
JOIN Infor AS Infor3 ON Infor2.customerid = Infor3.customerid
WHERE Infor1.description != Infor2.description
AND Infor1.description < Infor2.description
AND Infor2.description != Infor3.description
AND Infor2.description < Infor3.description
GROUP BY Infor1.description,
         Infor2.description,
         Infor3.description
ORDER BY 4 DESC;



