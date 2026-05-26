-- 1. Create db green_taxi_trips

CREATE DATABASE green_taxi_trips
USE green_taxi_trips
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
FROM 'D:\Project\Taxi_trips\2021_Green_Taxi_Trip_Data_20260522.csv'
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
FROM 'D:\Project\Taxi_trips\2021_Green_Taxi_Trip_Data_20260522.csv'
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

-- 9. Replace 'Y' / 'N' values with 1 / 0 and change column type from VARCHAR to BIT

UPDATE raw_trips
	SET store_and_fwd_flag = CASE store_and_fwd_flag
							 WHEN 'Y' THEN '1'
							 WHEN 'N' THEN '0'
							 ELSE store_and_fwd_flag
							 END
	WHERE store_and_fwd_flag IN ('Y', 'N')

ALTER TABLE raw_trips ALTER COLUMN store_and_fwd_flag BIT

-- 10. All values in column ehail_fee are NULL -> drop this column

ALTER TABLE raw_trips DROP column ehail_fee

-- 11. Standardize column names (snake_case)

EXEC sp_rename 'raw_trips.VendorID', 'vendor_id', 'COLUMN'
EXEC sp_rename 'raw_trips.RatecodeID', 'rate_code_id', 'COLUMN'
EXEC sp_rename 'raw_trips.PULocationID', 'pu_location_id', 'COLUMN'
EXEC sp_rename 'raw_trips.DOLocationID', 'do_location_id', 'COLUMN'

-- 12. Rename columns payment_type, trip_type (they contain identifiers, not types)

EXEC sp_rename 'raw_trips.payment_type', 'payment_type_id', 'COLUMN'
EXEC sp_rename 'raw_trips.trip_type', 'trip_type_id', 'COLUMN'

-- 13. Assign PRIMARY KEY for table raw_trips and fill it with incremental values

ALTER TABLE raw_trips ADD trip_id INT IDENTITY(1, 1) PRIMARY KEY 

-- 14. Replace physically impossible trip distances (>= 100 miles) with NULL

UPDATE raw_trips
SET trip_distance = NULL
WHERE trip_distance >= 80;

-- 2,155 rows affected. Values >= 80 miles are physically impossible for NYC taxi trips.

-- 15. Increment values in payment_type_id column (in order to be 1 as the first value, not 0)

UPDATE trips
SET payment_type_id = payment_type_id + 1
WHERE payment_type_id IS NOT NULL

-- 16. Rename table raw_trips -> trips

EXEC sp_rename 'dbo.raw_trips', 'trips' 

-- 17. View final schema

SELECT COLUMN_NAME, DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE
FROM INFORMATION_SCHEMA.COLUMNS 

-- 18. Create new tables to store the decoded descriptions of the IDs mentioned in the dataset's data dictionary and fill them with values

CREATE TABLE vendors (id INT PRIMARY KEY, name VARCHAR(100) NOT NULL)
CREATE TABLE rate_codes (id INT PRIMARY KEY, description VARCHAR(100) NOT NULL)
CREATE TABLE payment_types (id INT PRIMARY KEY, type VARCHAR(100) NOT NULL)
CREATE TABLE trip_types (id INT PRIMARY KEY, type VARCHAR(100) NOT NULL) 

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
							  (2, 'Dispatch') 

-- 19. Check that columns vendor_id, rate_code_id, payment_type_id and trip_type_id in table trips don’t contain values that are not listed
--     in tables vendors, rate_codes, payment_types and trip_types correspondingly.

SELECT DISTINCT trip_type_id, COUNT(*) AS unique_trip_type_id_cnt
FROM trips
GROUP BY trip_type_id
ORDER BY trip_type_id; 

-- 20. Value "5" in vendor_id not listed in vendors table -> it should be replaced with NULL. No issues with other columns found

UPDATE trips
SET vendor_id = NULL
WHERE vendor_id = 5

-- 21. Create foreign keys

ALTER TABLE trips ADD CONSTRAINT FK_trips_vendors FOREIGN KEY (vendor_id) REFERENCES vendors(id)
ALTER TABLE trips ADD CONSTRAINT FK_trips_rate_codes FOREIGN KEY (rate_code_id) REFERENCES rate_codes(id)
ALTER TABLE trips ADD CONSTRAINT FK_trips_payment_types FOREIGN KEY (payment_type_id) REFERENCES payment_types(id)
ALTER TABLE trips ADD CONSTRAINT FK_trips_trip_types FOREIGN KEY (trip_type_id) REFERENCES trip_types(id)