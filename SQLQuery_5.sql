-- SQL CLEANING DATA - REMOVING NULL AND NEGATIVE NUMBER IN PRICE AND QUANTITY
DELETE FROM Portfolio.dbo.OnlineRetail WHERE unitprice <= 0
DELETE FROM Portfolio.dbo.OnlineRetail WHERE description IS NULL

SELECT *
FROM Portfolio.dbo.OnlineRetail

-- In this case, I don't remove the null for customer id because it will affect the numbers of total sale. 
-- Additionally, I realized some negative quantity in the Invoiceno bginning with letter 'C', which is how the company fixes cancelaion in the order record by subtracting with the same unit numbers
-- However, some of these are considered as cost (discount, fee, bank charge) so I will excluded them

WITH CTE AS (
    SELECT *
    FROM Portfolio.dbo.OnlineRetail
)
DELETE FROM CTE
WHERE quantity <= 0 AND invoiceno NOT LIKE 'C%'


-- TOTAL REVENUE PER MONTH
 SELECT DATEADD(MONTH, DATEDIFF(MONTH, 0, invoicedate), 0)  as Sales_Month, 
         SUM(unitprice*quantity) as Sales
FROM Portfolio.dbo.OnlineRetail
GROUP BY DATEADD(MONTH, DATEDIFF(MONTH, 0, invoicedate), 0)
ORDER BY 1

-- TOTAL REVENUE PER COUNTRY
SELECT country, ROUND(SUM(unitprice*quantity),0) as Sales
FROM Portfolio.dbo.OnlineRetail
GROUP BY country
ORDER BY 2 desc;

-- ORDER VALUES PER CUSTOMER ACROSS DATASET
SELECT customerid, country, ROUND(SUM(unitprice*quantity),0) as Sales
FROM Portfolio.dbo.OnlineRetail
WHERE customerid IS NOT NULL
GROUP BY customerid, country
ORDER BY 3 desc;

-- HOW MANY UNIQUE PRODUCTS HAS EẠCH CUSTOMER PURCHASE
SELECT customerid,
     COUNT(description) as unique_number_product
FROM Portfolio.dbo.OnlineRetail
WHERE customerid IS NOT NULL
GROUP BY customerid, country
ORDER BY 2 desc;

-- HOW MANY ORDERS DOES EACH CUSTOMER HAVE
SELECT customerid, 
     COUNT(DISTINCT invoiceno) as orders_per_customer
FROM Portfolio.dbo.OnlineRetail
WHERE customerid IS NOT NULL
GROUP BY customerid, country
ORDER BY 2 desc;

-- WHICH CUSTOMER HAVE ONLY MADE A SINGLE PURCHASE FROM COMPANY
SELECT customerid, orders_per_customer, unique_number_product
FROM (
    SELECT 
        customerid,
        COUNT(DISTINCT invoiceno) as orders_per_customer,
        COUNT(DISTINCT description) as unique_number_product
    FROM Portfolio.dbo.OnlineRetail
    WHERE customerid IS NOT NULL
    GROUP BY customerid
) AS Subquery
WHERE orders_per_customer = 1
ORDER BY 3 DESC;

-- UNIQUE PRODUCTS PER ORDER
SELECT invoiceno, customerid, COUNT(DISTINCT description) as unique_number_product
FROM Portfolio.dbo.OnlineRetail
WHERE customerid IS NOT NULL
GROUP BY invoiceno, customerid
ORDER BY 3 DESC;

-- BEST SELLING PRODUCT
SELECT description, 
     SUM(quantity) as total_quantity_per_product, 
     ROUND(SUM(quantity * unitprice), 0) as sales_per_product, 
     COUNT(DISTINCT invoiceno) as distinct_product_ordes
FROM Portfolio.dbo.OnlineRetail
GROUP BY description
ORDER BY 2 DESC;

-- AVEREAGE INTERVAL BETWEEN EACH ORDER PER CUSTOMER (I only got one date for orders belonging to one customer id which happened many times on the same date to calculate)
SELECT customerid, 
      AVG(Interval) AS avg_interval_btw_each_order,
      COUNT(Interval) AS number_interval
FROM
(
    SELECT DISTINCT customerid,  
     invoicedate, 
     LEAD(invoicedate) over (partition by customerid order by invoicedate) as next_order_date,
     COALESCE(DATEDIFF(day, invoicedate, LEAD(invoicedate) over (partition by customerid order by invoicedate)),0) AS Interval
    FROM Portfolio.dbo.OnlineRetail
    WHERE customerid is not NULL
) a
WHERE interval != 0
GROUP BY customerid

-- BASKET ANALYSIS FOR RETAIL CUSTOMERS WHO MADE SINGLE PURCHASE 
 WITH Order_List AS 
(
SELECT customerid, orders_per_customer, unique_number_product
FROM (
    SELECT 
        customerid,
        COUNT(DISTINCT invoiceno) as orders_per_customer,
        COUNT(DISTINCT description) as unique_number_product
    FROM Portfolio.dbo.OnlineRetail
    WHERE customerid IS NOT NULL 
    GROUP BY customerid, country
    HAVING COUNT(DISTINCT description) >= 3
) AS Subquery
WHERE orders_per_customer = 1 
)
, Infor AS 
(
SELECT Order_List.customerid, FIS.description
FROM Order_List
JOIN Portfolio.dbo.OnlineRetail AS FIS ON Order_List.customerid = FIS.customerid
)

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

SELECT *
FROM Portfolio.dbo.OnlineRetail










