CREATE PROCEDURE [tmd].[sp_m3_BirthRate_Projections]
/*********************************************************************************
Written by: Amanda Selle, SUSS
2/5/2021
Purpose: Calculate projected U.S. Birth and Fertility Rates.

Change Log:

**********************************************************************************/
AS

DECLARE @maxYear_Proj		INT
DECLARE @maxYear_Actual		INT
DECLARE @FR_Slope			DECIMAL(26,18)
DECLARE @FR_Intercept		DECIMAL(26,18)
DECLARE @FR_STDEV			DECIMAL(26,18)
DECLARE @BR_Slope			DECIMAL(26,18)
DECLARE @BR_Intercept		DECIMAL(26,18)
DECLARE @BR_STDEV			DECIMAL(26,18)
DECLARE @minYear_Proj		INT
DECLARE @minYear_Actual		INT
DECLARE @minYear_Base		INT


--===================================================================
-- DEFINE TABLE VARIABLES TO STORE CALCULATIONS
--===================================================================
DECLARE @fertility  TABLE (
	[YEAR]							INT NOT NULL,
	[Births]						INT NOT NULL,
	[Child Bearing]					INT NOT NULL,
	[Parents]						INT NOT NULL,
	[Population]					INT NOT NULL,
	[YEAREND]						DATE NOT NULL,
	[Fertility Rate]				DECIMAL(26,18) NOT NULL,
	[Birth Rate per 1K]				DECIMAL(26,18) NOT NULL,
	[Fertility Rate_5Rolling]		DECIMAL(26,18) NULL,
	[Birth Rate_5Rolling]			DECIMAL(26,18) NULL
)

DECLARE @calculations TABLE (
	FR_slope				DECIMAL(26,18) NOT NULL,
	BR_slope				DECIMAL(26,18) NOT NULL,
	FR_intercept			DECIMAL(26,18) NOT NULL,
	BR_intercept			DECIMAL(26,18) NOT NULL
)

DECLARE @birthRateProjections TABLE (
	[YEAR]					INT NOT NULL,
	[YEAR_Proj]				INT NULL,
	[B_Source]				VARCHAR(MAX) NOT NULL,
	[Rate]					DECIMAL(26,18) NOT NULL,
	[STDEV_1UP]				DECIMAL(26,18) NULL,
	[STDEV_1DOWN]			DECIMAL(26,18) NULL
);

--=====================================================================================


-- INSERT BIRTH/FERTILITY RATE DATA INTO TABLE VARIABLE
INSERT INTO @fertility
SELECT * FROM OPENROWSET ('SQLNCLI11','Server=<DATABASE_INSTANCE>;TRUSTED_CONNECTION=YES;','set fmtonly off EXEC <DATABASE>.<SCHEMA>.<SPROC> ')



SET @maxYear_Actual = (SELECT MAX([YEAR]) FROM @fertility WHERE [Births] > 0);
SET @minYear_Actual = (SELECT MIN([YEAR]) FROM @fertility WHERE [Fertility Rate_5Rolling] IS NOT NULL AND [Birth Rate_5Rolling] IS NOT NULL );





--==================================================================================================
-- PERFORM LINEAR LEAST SQUARES REGRESSION TO FIND THE SLOP AND INTERCEPT OF 
--		THE LINE OF BEST FIT
--		INSERT SLOPE AND INTERCEPTS INTO CALCULATIONS TABLE VARIABLE
--=====================================================================================================
INSERT INTO @calculations

SELECT
	FR_slope,
	BR_slope,
	yFR_bar - xbar * FR_slope AS FR_intercept,
	yBR_bar - xbar * BR_slope AS BR_intercept
FROM (
	SELECT
		SUM((x - xbar) * (yFR - yFR_bar)) / SUM((x - xbar) * (x - xbar)) AS FR_slope,
		SUM((x - xbar) * (yBR - yBR_bar)) / SUM((x - xbar) * (x - xbar)) AS BR_slope,
		MAX(yFR_bar)	AS yFR_bar,
		MAX(yBR_bar)	AS yBR_bar,
		MAX(xbar)		AS xbar
	FROM (
		SELECT 
			AVG([Fertility Rate_5Rolling]) OVER () AS yFR_bar,
			[Fertility Rate_5Rolling] AS yFR,
			AVG([Birth Rate_5Rolling]) OVER () AS yBR_bar,
			[Birth Rate_5Rolling] AS yBR,
			AVG([YEAR]) OVER () AS xbar,
			[YEAR] AS x
		FROM @fertility
		WHERE [YEAR] < ( @maxYear_Actual + 1 )
			and [YEAR] >= @minYear_Actual
		) AS x
	) AS y
--============================================================================================================================


--============================================================================================================================
-- SET SLOPE, INTERCEPT, AND STDEV VARIABLES TO BUILD PROJECTION EQUATIONS
--============================================================================================================================

-- BIRTH RATE EQUATION
SET @BR_Slope = (
SELECT BR_Slope FROM @calculations 
)
SET @BR_Intercept = (
SELECT BR_intercept FROM @calculations
)
SET @BR_STDEV = ( SELECT STDEV([Birth Rate per 1K]) FROM @fertility WHERE [YEAR] < ( @maxYear_Actual + 1 ) )


-- FERTILITY RATE EQUATION
SET @FR_Slope = (
SELECT FR_slope FROM @calculations
)
SET @FR_Intercept = (
SELECT FR_intercept FROM @calculations
)
SET @FR_STDEV = ( SELECT STDEV([Fertility Rate]) FROM @fertility WHERE [YEAR] < ( @maxYear_Actual + 1 ) )

--===========================================================================================================================



SET @minYear_Proj = @maxYear_Actual
SET @minYear_Base = @maxYear_Actual + 1
SET @maxYear_Proj = @minYear_Proj + 21



--===============================================================================================================================
-- ESTIMATE BIRTH AND FERTILITY RATES USING SLOPE, INTERCEPT, AND FUTURE YEAR
--		INSERT RECORDS DURING EACH ITERATION FOR SENSITIVITY ANALYSIS RATES
--===============================================================================================================================

WHILE @minYear_Proj <= @maxYear_Proj
BEGIN

INSERT INTO @birthRateProjections
([YEAR], [YEAR_Proj], [B_Source], [Rate], [STDEV_1UP], [STDEV_1DOWN] )
VALUES
-- ============== KNOWN ===============================================
(
	@minYear_Proj,
	@minYear_Proj + 1,
	'SUIT Crude Birth Rate',
	( @BR_Slope * @minYear_Proj ) + @BR_Intercept,
	( ( @BR_Slope * @minYear_Proj ) + @BR_Intercept ) + @BR_STDEV,
	( ( @BR_Slope * @minYear_Proj ) + @BR_Intercept ) - @BR_STDEV
),
(
	@minYear_Proj,
	@minYear_Proj + 1,
	'SUIT Fertility Rate',
	( @FR_Slope * @minYear_Proj ) + @FR_Intercept,
	( ( @FR_Slope * @minYear_Proj ) + @FR_Intercept ) + @FR_STDEV,
	( ( @FR_Slope * @minYear_Proj ) + @FR_Intercept ) - @FR_STDEV
),
-- ============== SENSITIVITY ANALYSIS ================================
(
	@minYear_Proj,
	@minYear_Proj + 1,
	'SUIT Crude Birth Rate + 2',
	( ( @BR_Slope * @minYear_Proj ) + @BR_Intercept ) + 2,
	( ( ( @BR_Slope * @minYear_Proj ) + @BR_Intercept ) + @BR_STDEV ) + 2,
	( ( ( @BR_Slope * @minYear_Proj ) + @BR_Intercept ) - @BR_STDEV ) + 2
),
(
	@minYear_Proj,
	@minYear_Proj + 1,
	'SUIT Fertility Rate + 2%',
	( ( @FR_Slope * @minYear_Proj ) + @FR_Intercept ) + 0.02,
	( ( ( @FR_Slope * @minYear_Proj ) + @FR_Intercept ) + @FR_STDEV ) + 0.02,
	( ( ( @FR_Slope * @minYear_Proj ) + @FR_Intercept ) - @FR_STDEV ) + 0.02
),
(
	@minYear_Proj,
	@minYear_Proj + 1,
	'SUIT Crude Birth Rate - 2',
	( ( @BR_Slope * @minYear_Proj ) + @BR_Intercept ) - 2,
	( ( ( @BR_Slope * @minYear_Proj ) + @BR_Intercept ) + @BR_STDEV ) - 2,
	( ( ( @BR_Slope * @minYear_Proj ) + @BR_Intercept ) - @BR_STDEV ) - 2
),
(
	@minYear_Proj,
	@minYear_Proj + 1,
	'SUIT Fertility Rate - 2%',
	( ( @FR_Slope * @minYear_Proj ) + @FR_Intercept ) - 0.02,
	( ( ( @FR_Slope * @minYear_Proj ) + @FR_Intercept ) + @FR_STDEV ) - 0.02,
	( ( ( @FR_Slope * @minYear_Proj ) + @FR_Intercept ) - @FR_STDEV ) - 0.02
)

SET @minYear_Proj = @minYear_Proj + 1

END

--============================================================================================================================



SELECT 
	[YEAR],
	YEAR_Proj,
	[B_Source],
	[Rate],
	[STDEV_1UP],
	[STDEV_1DOWN]
FROM @birthRateProjections



GO
