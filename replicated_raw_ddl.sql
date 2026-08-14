-- =============================================================================
-- DDL: REPLICATED database + RAW schema + all base tables
-- =============================================================================
-- Source of truth : snowflake.demo -> GET_DDL('SCHEMA','REPLICATED.RAW', TRUE)
-- Target dialect  : Snowflake
-- Objects         : 1 database, 1 schema, 9 base tables
--                   (9 PKs, 12 FKs, all column/table comments preserved)
--
-- Table creation order below is dependency-safe: parents before children, so
-- the inline FOREIGN KEY constraints resolve on a clean deploy.
--
--   Level 0 (no FK deps) : RAW_PHARMACY, RAW_PAYER, RAW_DRUG, RAW_PRESCRIBER
--   Level 1              : RAW_PATIENT        -> PHARMACY, PAYER
--   Level 2              : RAW_PRESCRIPTION   -> PHARMACY, PRESCRIBER, DRUG, PATIENT
--                          RAW_INVENTORY      -> PHARMACY, DRUG
--   Level 3              : RAW_DISPENSE       -> PRESCRIPTION, DRUG
--   Level 4              : RAW_CLAIM          -> DISPENSE, PATIENT, PAYER
--
-- IDEMPOTENCY: uses CREATE ... IF NOT EXISTS, so re-running is a safe no-op and
-- will NOT drop data. To force a rebuild instead, replace "CREATE TABLE IF NOT
-- EXISTS" with "CREATE OR REPLACE TABLE" (destructive -- existing rows are lost).
--
-- RETARGETING: to deploy this schema under a different database name, change
-- only the two statements in section 1 (and the USE DATABASE line). All table
-- DDL below is unqualified and resolves against the active schema context.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Database + schema
-- -----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS REPLICATED
    COMMENT = 'Zero-copy replica of PHARMA_DATA.RAW created by Genesis (Eve)';

USE DATABASE REPLICATED;

CREATE SCHEMA IF NOT EXISTS RAW
    COMMENT = 'Raw landing zone replicated from the PHARMA_DATA source system.';

USE SCHEMA RAW;


-- -----------------------------------------------------------------------------
-- 2. Level 0 -- independent reference / master tables (no FK dependencies)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS RAW_PHARMACY (
    PHARMACY_ID       NUMBER(38,0)  NOT NULL COMMENT 'Surrogate pharmacy id (PK).',
    SOURCE_SYSTEM_ID  VARCHAR(20)   NOT NULL COMMENT 'Identifier of the originating Oracle OLTP instance.',
    NCPDP_ID          VARCHAR(7),
    NPI               VARCHAR(10),
    PHARMACY_NAME     VARCHAR(200),
    ADDRESS_LINE1     VARCHAR(200),
    CITY              VARCHAR(100),
    STATE             VARCHAR(2),
    ZIP               VARCHAR(10),
    PHONE             VARCHAR(20),
    STORE_TYPE        VARCHAR(20)   COMMENT 'chain | independent | health_system.',
    RELEASE_VERSION   VARCHAR(20)   COMMENT 'Product release running on this source (drives schema drift).',
    IS_ACTIVE         BOOLEAN,
    CDC_OPERATION     VARCHAR(1),
    CDC_TIMESTAMP     TIMESTAMP_NTZ(9),
    CDC_SEQUENCE      NUMBER(38,0),
    _LOADED_AT        TIMESTAMP_NTZ(9),
    CONSTRAINT PK_RAW_PHARMACY PRIMARY KEY (PHARMACY_ID)
)
COMMENT = 'Raw landing: pharmacy/store instances; one per Oracle source system.';


CREATE TABLE IF NOT EXISTS RAW_PAYER (
    PAYER_ID          NUMBER(38,0)  NOT NULL,
    PAYER_NAME        VARCHAR(200),
    PAYER_TYPE        VARCHAR(20),
    BIN               VARCHAR(6)    COMMENT 'Bank Identification Number for pharmacy claim routing.',
    PCN               VARCHAR(10)   COMMENT 'Processor Control Number for claim routing.',
    CDC_OPERATION     VARCHAR(1),
    CDC_TIMESTAMP     TIMESTAMP_NTZ(9),
    CDC_SEQUENCE      NUMBER(38,0),
    SOURCE_SYSTEM_ID  VARCHAR(20),
    _LOADED_AT        TIMESTAMP_NTZ(9),
    CONSTRAINT PK_RAW_PAYER PRIMARY KEY (PAYER_ID)
)
COMMENT = 'Raw landing: insurance payers and pharmacy benefit managers.';


CREATE TABLE IF NOT EXISTS RAW_DRUG (
    DRUG_ID           NUMBER(38,0)  NOT NULL,
    NDC               VARCHAR(15)   COMMENT 'National Drug Code (11 digit, 5-4-2 segments).',
    DRUG_NAME         VARCHAR(200),
    GENERIC_NAME      VARCHAR(200),
    MANUFACTURER      VARCHAR(200),
    DOSAGE_FORM       VARCHAR(50),
    STRENGTH          VARCHAR(50),
    ROUTE             VARCHAR(50),
    DEA_SCHEDULE      VARCHAR(4)    COMMENT 'Controlled-substance schedule: NULL (non-controlled) or CII-CV.',
    IS_GENERIC        BOOLEAN,
    AWP_UNIT_PRICE    NUMBER(12,4)  COMMENT 'Average Wholesale Price per unit.',
    CDC_OPERATION     VARCHAR(1),
    CDC_TIMESTAMP     TIMESTAMP_NTZ(9),
    CDC_SEQUENCE      NUMBER(38,0),
    SOURCE_SYSTEM_ID  VARCHAR(20),
    _LOADED_AT        TIMESTAMP_NTZ(9),
    CONSTRAINT PK_RAW_DRUG PRIMARY KEY (DRUG_ID)
)
COMMENT = 'Raw landing: drug catalog keyed by National Drug Code.';


CREATE TABLE IF NOT EXISTS RAW_PRESCRIBER (
    PRESCRIBER_ID     NUMBER(38,0)  NOT NULL,
    NPI               VARCHAR(10)   COMMENT 'National Provider Identifier (10 digit).',
    DEA_NUMBER        VARCHAR(9)    COMMENT 'DEA registration; required to prescribe controlled substances.',
    FIRST_NAME        VARCHAR(100),
    LAST_NAME         VARCHAR(100),
    SPECIALTY         VARCHAR(100),
    STATE_LICENSE     VARCHAR(20),
    ADDRESS_LINE1     VARCHAR(200),
    CITY              VARCHAR(100),
    STATE             VARCHAR(2),
    ZIP               VARCHAR(10),
    CDC_OPERATION     VARCHAR(1),
    CDC_TIMESTAMP     TIMESTAMP_NTZ(9),
    CDC_SEQUENCE      NUMBER(38,0),
    SOURCE_SYSTEM_ID  VARCHAR(20),
    _LOADED_AT        TIMESTAMP_NTZ(9),
    CONSTRAINT PK_RAW_PRESCRIBER PRIMARY KEY (PRESCRIBER_ID)
)
COMMENT = 'Raw landing: prescribing providers (physician/NP/PA).';


-- -----------------------------------------------------------------------------
-- 3. Level 1 -- depends on PHARMACY + PAYER
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS RAW_PATIENT (
    PATIENT_ID        NUMBER(38,0)  NOT NULL,
    PHARMACY_ID       NUMBER(38,0)  COMMENT 'FK-like reference to RAW_PHARMACY.',
    FIRST_NAME        VARCHAR(100),
    LAST_NAME         VARCHAR(100),
    DATE_OF_BIRTH     DATE,
    GENDER            VARCHAR(1),
    ADDRESS_LINE1     VARCHAR(200),
    CITY              VARCHAR(100),
    STATE             VARCHAR(2),
    ZIP               VARCHAR(10),
    PHONE             VARCHAR(20),
    EMAIL             VARCHAR(200),
    PRIMARY_PAYER_ID  NUMBER(38,0)  COMMENT 'FK-like reference to RAW_PAYER.',
    ENROLL_DATE       DATE,
    CDC_OPERATION     VARCHAR(1),
    CDC_TIMESTAMP     TIMESTAMP_NTZ(9),
    CDC_SEQUENCE      NUMBER(38,0),
    SOURCE_SYSTEM_ID  VARCHAR(20),
    _LOADED_AT        TIMESTAMP_NTZ(9),
    CONSTRAINT PK_RAW_PATIENT       PRIMARY KEY (PATIENT_ID),
    CONSTRAINT FK_PATIENT_PHARMACY  FOREIGN KEY (PHARMACY_ID)      REFERENCES RAW_PHARMACY (PHARMACY_ID),
    CONSTRAINT FK_PATIENT_PAYER     FOREIGN KEY (PRIMARY_PAYER_ID) REFERENCES RAW_PAYER (PAYER_ID)
)
COMMENT = 'Raw landing: pharmacy patients. Synthetic PII only.';


-- -----------------------------------------------------------------------------
-- 4. Level 2 -- depends on PHARMACY / PRESCRIBER / DRUG / PATIENT
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS RAW_PRESCRIPTION (
    PRESCRIPTION_ID     NUMBER(38,0) NOT NULL,
    RX_NUMBER           VARCHAR(20)  COMMENT 'Human-facing prescription number.',
    PHARMACY_ID         NUMBER(38,0),
    PATIENT_ID          NUMBER(38,0),
    PRESCRIBER_ID       NUMBER(38,0),
    DRUG_ID             NUMBER(38,0),
    WRITTEN_DATE        DATE,
    EXPIRATION_DATE     DATE,
    QUANTITY_PRESCRIBED NUMBER(12,2),
    DAYS_SUPPLY         NUMBER(5,0),
    REFILLS_AUTHORIZED  NUMBER(3,0),
    REFILLS_REMAINING   NUMBER(3,0),
    RX_STATUS           VARCHAR(20),
    SIG_TEXT            VARCHAR(500),
    ORIGIN              VARCHAR(20)  COMMENT 'How the Rx was received: electronic | phone | fax | written.',
    CDC_OPERATION       VARCHAR(1),
    CDC_TIMESTAMP       TIMESTAMP_NTZ(9),
    CDC_SEQUENCE        NUMBER(38,0),
    SOURCE_SYSTEM_ID    VARCHAR(20),
    _LOADED_AT          TIMESTAMP_NTZ(9),
    CONSTRAINT PK_RAW_PRESCRIPTION PRIMARY KEY (PRESCRIPTION_ID),
    CONSTRAINT FK_RX_PHARMACY      FOREIGN KEY (PHARMACY_ID)   REFERENCES RAW_PHARMACY (PHARMACY_ID),
    CONSTRAINT FK_RX_PRESCRIBER    FOREIGN KEY (PRESCRIBER_ID) REFERENCES RAW_PRESCRIBER (PRESCRIBER_ID),
    CONSTRAINT FK_RX_DRUG          FOREIGN KEY (DRUG_ID)       REFERENCES RAW_DRUG (DRUG_ID),
    CONSTRAINT FK_RX_PATIENT       FOREIGN KEY (PATIENT_ID)    REFERENCES RAW_PATIENT (PATIENT_ID)
)
COMMENT = 'Raw landing: prescription (Rx) orders.';


CREATE TABLE IF NOT EXISTS RAW_INVENTORY (
    INVENTORY_ID       NUMBER(38,0) NOT NULL,
    PHARMACY_ID        NUMBER(38,0),
    DRUG_ID            NUMBER(38,0),
    QUANTITY_ON_HAND   NUMBER(12,2) COMMENT 'Current units on hand.',
    REORDER_LEVEL      NUMBER(12,2),
    LAST_RECEIVED_DATE DATE,
    UNIT_COST          NUMBER(12,4),
    LOT_NUMBER         VARCHAR(30),
    EXPIRATION_DATE    DATE,
    CDC_OPERATION      VARCHAR(1),
    CDC_TIMESTAMP      TIMESTAMP_NTZ(9),
    CDC_SEQUENCE       NUMBER(38,0),
    SOURCE_SYSTEM_ID   VARCHAR(20),
    _LOADED_AT         TIMESTAMP_NTZ(9),
    CONSTRAINT PK_RAW_INVENTORY  PRIMARY KEY (INVENTORY_ID),
    CONSTRAINT FK_INV_DRUG       FOREIGN KEY (DRUG_ID)     REFERENCES RAW_DRUG (DRUG_ID),
    CONSTRAINT FK_INV_PHARMACY   FOREIGN KEY (PHARMACY_ID) REFERENCES RAW_PHARMACY (PHARMACY_ID)
)
COMMENT = 'Raw landing: per-pharmacy on-hand drug inventory.';


-- -----------------------------------------------------------------------------
-- 5. Level 3 -- depends on PRESCRIPTION + DRUG
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS RAW_DISPENSE (
    DISPENSE_ID        NUMBER(38,0) NOT NULL,
    PRESCRIPTION_ID    NUMBER(38,0),
    PHARMACY_ID        NUMBER(38,0),
    FILL_NUMBER        NUMBER(3,0)  COMMENT 'Fill sequence (0 = original fill, 1..n = refills).',
    FILL_DATE          DATE,
    QUANTITY_DISPENSED NUMBER(12,2),
    DAYS_SUPPLY        NUMBER(5,0),
    DISPENSED_DRUG_ID  NUMBER(38,0),
    PHARMACIST_ID      VARCHAR(20),
    INGREDIENT_COST    NUMBER(12,2),
    DISPENSING_FEE     NUMBER(8,2),
    DISPENSE_STATUS    VARCHAR(20),
    CDC_OPERATION      VARCHAR(1),
    CDC_TIMESTAMP      TIMESTAMP_NTZ(9),
    CDC_SEQUENCE       NUMBER(38,0),
    SOURCE_SYSTEM_ID   VARCHAR(20),
    _LOADED_AT         TIMESTAMP_NTZ(9),
    CONSTRAINT PK_RAW_DISPENSE PRIMARY KEY (DISPENSE_ID),
    CONSTRAINT FK_DISP_DRUG    FOREIGN KEY (DISPENSED_DRUG_ID) REFERENCES RAW_DRUG (DRUG_ID),
    CONSTRAINT FK_DISP_RX      FOREIGN KEY (PRESCRIPTION_ID)   REFERENCES RAW_PRESCRIPTION (PRESCRIPTION_ID)
)
COMMENT = 'Raw landing: dispense/fill events against prescriptions.';


-- -----------------------------------------------------------------------------
-- 6. Level 4 -- depends on DISPENSE + PATIENT + PAYER
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS RAW_CLAIM (
    CLAIM_ID             NUMBER(38,0) NOT NULL,
    DISPENSE_ID          NUMBER(38,0),
    PATIENT_ID           NUMBER(38,0),
    PAYER_ID             NUMBER(38,0),
    CLAIM_DATE           DATE,
    CLAIM_STATUS         VARCHAR(20),
    SUBMITTED_AMOUNT     NUMBER(12,2),
    INGREDIENT_COST_PAID NUMBER(12,2),
    DISPENSING_FEE_PAID  NUMBER(8,2),
    COPAY_AMOUNT         NUMBER(8,2),
    AMOUNT_PAID          NUMBER(12,2) COMMENT 'Net paid = ingredient_cost_paid + dispensing_fee_paid - copay.',
    REJECT_CODE          VARCHAR(10)  COMMENT 'NCPDP-style reject code (populated when CLAIM_STATUS = rejected).',
    GROUP_ID             VARCHAR(20),
    CDC_OPERATION        VARCHAR(1),
    CDC_TIMESTAMP        TIMESTAMP_NTZ(9),
    CDC_SEQUENCE         NUMBER(38,0),
    SOURCE_SYSTEM_ID     VARCHAR(20),
    _LOADED_AT           TIMESTAMP_NTZ(9),
    CONSTRAINT PK_RAW_CLAIM     PRIMARY KEY (CLAIM_ID),
    CONSTRAINT FK_CLAIM_PATIENT FOREIGN KEY (PATIENT_ID)  REFERENCES RAW_PATIENT (PATIENT_ID),
    CONSTRAINT FK_CLAIM_DISP    FOREIGN KEY (DISPENSE_ID)  REFERENCES RAW_DISPENSE (DISPENSE_ID),
    CONSTRAINT FK_CLAIM_PAYER   FOREIGN KEY (PAYER_ID)     REFERENCES RAW_PAYER (PAYER_ID)
)
COMMENT = 'Raw landing: adjudicated pharmacy insurance claims.';


-- =============================================================================
-- 7. Post-deploy validation
-- =============================================================================
-- Expect 9 rows, all TABLE_TYPE = 'BASE TABLE'
-- SELECT TABLE_NAME, TABLE_TYPE, ROW_COUNT
-- FROM REPLICATED.INFORMATION_SCHEMA.TABLES
-- WHERE TABLE_SCHEMA = 'RAW' AND TABLE_TYPE = 'BASE TABLE'
-- ORDER BY TABLE_NAME;
--
-- Expect 9 PK + 12 FK constraints
-- SHOW PRIMARY KEYS IN SCHEMA REPLICATED.RAW;
-- SHOW IMPORTED KEYS IN SCHEMA REPLICATED.RAW;
-- =============================================================================
