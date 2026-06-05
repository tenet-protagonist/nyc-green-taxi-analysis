-- 1. Create db green_taxi_trips
CREATE DATABASE green_taxi_trips_2023
USE green_taxi_trips_2023
GO

-- 2. Create table raw_trips

CREATE TABLE raw_trips (
	VendorID INT,
	lpep_pickup_datetime DATETIME,
	lpep_dropoff_datetime DATETIME,
	store_and_fwd_flag CHAR(1),
	RatecodeID INT,
	PULocationID INT,
	DOLocationID INT,
	passenger_count INT,
	trip_distance DECIMAL(8, 2),                                                          
	fare_amount DECIMAL(8, 2),                                                           
	extra DECIMAL(8, 2),
	mta_tax DECIMAL(4, 2),
	tip_amount DECIMAL(10, 2),
	tolls_amount DECIMAL(6, 2),
	ehail_fee VARCHAR(10),
	improvement_surcharge DECIMAL(6, 2),
	total_amount DECIMAL(8, 2),
	payment_type INTEGER,
	trip_type INTEGER,
	congestion_surcharge DECIMAL(4, 2)
)

-- 3. Import values from csv

BULK INSERT raw_trips
FROM 'D:\Project\Taxi_trips\2023_Green_Taxi_Trip_Data_20260528.csv'
WITH (
		FORMAT = 'CSV',
		ROWTERMINATOR = '0x0a',
		FIELDTERMINATOR = ',',
		FIELDQUOTE = '"',
		FIRSTROW = 2
	 ) 

-- 4. Result: failed. Some errors occured. Change columns type

ALTER TABLE raw_trips ALTER COLUMN trip_distance VARCHAR(10)
ALTER TABLE raw_trips ALTER COLUMN fare_amount VARCHAR(10)
ALTER TABLE raw_trips ALTER COLUMN total_amount VARCHAR(10)

-- 5. Import values again

BULK INSERT raw_trips
FROM 'D:\Project\Taxi_trips\2023_Green_Taxi_Trip_Data_20260528.csv'
WITH (
		FORMAT = 'CSV',
		ROWTERMINATOR = '0x0a',
		FIELDTERMINATOR = ',',
		FIELDQUOTE = '"',
		FIRSTROW = 2
	 ) 

-- 6. Create procedure to check for other unexpected chars

CREATE PROCEDURE usp_CheckForOtherChars
    @TableName NVARCHAR(100)
AS
BEGIN
    DECLARE @query NVARCHAR(MAX);

    SELECT @query = 'SELECT ' + STRING_AGG(
											 'ISNULL((SELECT TOP 1 1
													  FROM ' + @TableName +
													  ' WHERE ' + COLUMN_NAME + ' LIKE ''%[^0-9.,-]%''
													 ), 0) AS ' + COLUMN_NAME,
											 ', '
										  )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = @TableName
      AND COLUMN_NAME IN ('trip_distance', 'fare_amount', 'total_amount');

    EXEC sp_executesql @query;
END;

EXEC usp_CheckForOtherChars @TableName = 'raw_trips'

-- 7. Remove commas

UPDATE raw_trips SET trip_distance = REPLACE(trip_distance, ',', '') WHERE trip_distance LIKE '%,%'
UPDATE raw_trips SET fare_amount = REPLACE(fare_amount, ',', '') WHERE fare_amount LIKE '%,%'
UPDATE raw_trips SET total_amount = REPLACE(total_amount, ',', '') WHERE total_amount LIKE '%,%';

-- 8. Return previous types

ALTER TABLE raw_trips ALTER COLUMN trip_distance DECIMAL(8, 2)
ALTER TABLE raw_trips ALTER COLUMN fare_amount DECIMAL(8, 2)
ALTER TABLE raw_trips ALTER COLUMN total_amount DECIMAL(9, 2)

-- 9. All values in column ehail_fee are NULL -> drop this column

ALTER TABLE raw_trips DROP column ehail_fee

-- 10. Standardize column names (snake_case)

EXEC sp_rename 'raw_trips.VendorID', 'vendor_id', 'COLUMN'
EXEC sp_rename 'raw_trips.RatecodeID', 'rate_code_id', 'COLUMN'
EXEC sp_rename 'raw_trips.PULocationID', 'pu_location_id', 'COLUMN'
EXEC sp_rename 'raw_trips.DOLocationID', 'do_location_id', 'COLUMN'

-- 11. Rename columns payment_type, trip_type (they contain identifiers, not types)

EXEC sp_rename 'raw_trips.payment_type', 'payment_type_id', 'COLUMN'
EXEC sp_rename 'raw_trips.trip_type', 'trip_type_id', 'COLUMN'

-- 12. Assign PRIMARY KEY for table raw_trips and fill it with incremental values

ALTER TABLE raw_trips ADD trip_id INT IDENTITY(1, 1) PRIMARY KEY 

-- 13.1. Replace physically impossible trip distances (>= 100 miles) with NULL

UPDATE raw_trips
SET trip_distance = NULL
WHERE trip_distance >= 100

-- 582 rows affected. Values >= 100 miles are physically impossible for NYC taxi trips.

-- 13.1. Tips are actual for credit card payments -> fill NULL values with credit card payment type id where tip_amount is greater than 0
UPDATE raw_trips
SET payment_type_id = 2
FROM raw_trips
WHERE tip_amount <> 0 AND payment_type_id IS NULL

-- Other NULL values fill with 'Unknown' type

UPDATE raw_trips
SET payment_type_id = 6
WHERE payment_type_id IS NULL

UPDATE raw_trips
SET trip_type_id = 3
WHERE trip_type_id IS NULL

-- 13.2. Remove rows where trip_distance <= 0 / fare_amount <= 0 / total_amount <= 0

DELETE FROM raw_trips
WHERE (trip_distance <= 0) OR (fare_amount <= 0) OR (total_amount <= 0)

-- 13.3. Remove rows with invalid dates

DELETE FROM raw_trips
WHERE lpep_pickup_datetime < '2023-01-01' OR lpep_pickup_datetime >= '2024-01-01' OR
	  lpep_dropoff_datetime < '2023-01-01' OR lpep_dropoff_datetime >= '2024-01-01'

-- 13.4. Drop columns that will not be used
ALTER TABLE raw_trips
DROP COLUMN store_and_fwd_flag, extra, mta_tax, tip_amount, tolls_amount, improvement_surcharge, congestion_surcharge

-- 18 rows affected

-- 14. Increment values in payment_type_id column (in order to be 1 as the first value, not 0)

UPDATE raw_trips
SET payment_type_id = payment_type_id + 1
WHERE payment_type_id IS NOT NULL

-- 15. Rename table raw_trips -> trips

EXEC sp_rename 'dbo.raw_trips', 'trips' 

-- 16. View final schema

SELECT COLUMN_NAME, DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE
FROM INFORMATION_SCHEMA.COLUMNS 

-- 17. Create new tables to store the decoded descriptions of the IDs mentioned in the dataset's data dictionary and fill them with values

CREATE TABLE vendors (id INT PRIMARY KEY, name VARCHAR(100) NOT NULL)
CREATE TABLE rate_codes (id INT PRIMARY KEY, description VARCHAR(100) NOT NULL)
CREATE TABLE payment_types (id INT PRIMARY KEY, type VARCHAR(100) NOT NULL)
CREATE TABLE trip_types (id INT PRIMARY KEY, type VARCHAR(100) NOT NULL)
CREATE TABLE zones (id INT PRIMARY KEY, borough VARCHAR(50), zone VARCHAR(50), service_zone VARCHAR(30))

INSERT INTO vendors VALUES (1, 'Creative Mobile Technologies, LLC'),
						   (2, 'VeriFone Inc.')
INSERT INTO rate_codes VALUES (1, 'Standard rate'),
							  (2, 'JFK'),
							  (3, 'Newark'),
							  (4, 'Nassau or Westchester'),
							  (5, 'Negotiated fare'),
							  (6, 'Group ride'),
							  (99, 'Null/unknown')
INSERT INTO payment_types VALUES (1, 'Flex Fare trip'),
								 (2, 'Credit card'),
								 (3, 'Cash'),
								 (4, 'No charge'),
								 (5, 'Dispute'),
								 (6, 'Unknown'),
								 (7, 'Voided trip')
INSERT INTO trip_types VALUES (1, 'Street-hail'),
							  (2, 'Dispatch'),
							  (3, 'Unknown')

BULK INSERT zones
FROM 'D:\Project\Taxi_trips\taxi_zone_lookup.csv'
WITH (
    FORMAT = 'CSV',
    FIELDTERMINATOR = ',',
    FIELDQUOTE = '"',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2
);

-- 18. Check that columns vendor_id, rate_code_id, payment_type_id and trip_type_id in table trips don’t contain values that are not listed
--     in tables vendors, rate_codes, payment_types and trip_types correspondingly.

SELECT DISTINCT vendor_id, COUNT(*) AS unique_vendor_id_cnt
FROM trips
GROUP BY vendor_id
ORDER BY vendor_id;

SELECT DISTINCT rate_code_id, COUNT(*) AS unique_rate_code_id_cnt
FROM trips
GROUP BY rate_code_id
ORDER BY rate_code_id; 

SELECT DISTINCT payment_type_id, COUNT(*) AS unique_payment_type_id_cnt
FROM trips
GROUP BY payment_type_id
ORDER BY payment_type_id; 

SELECT DISTINCT trip_type_id, COUNT(*) AS unique_trip_type_id_cnt
FROM trips
GROUP BY trip_type_id
ORDER BY trip_type_id; 

-- 19. Create foreign keys

ALTER TABLE trips ADD CONSTRAINT FK_trips_vendors FOREIGN KEY (vendor_id) REFERENCES vendors(id)
ALTER TABLE trips ADD CONSTRAINT FK_trips_rate_codes FOREIGN KEY (rate_code_id) REFERENCES rate_codes(id)
ALTER TABLE trips ADD CONSTRAINT FK_trips_payment_types FOREIGN KEY (payment_type_id) REFERENCES payment_types(id)
ALTER TABLE trips ADD CONSTRAINT FK_trips_trip_types FOREIGN KEY (trip_type_id) REFERENCES trip_types(id)
ALTER TABLE trips ADD CONSTRAINT FK_trips_pu_zones FOREIGN KEY (pu_location_id) REFERENCES zones(id)