-- Updated Gold DDL (no structural changes applied in this run)
-- Source of truth: DI_LakehouseInaDay_snowflake/Inputs/gold ddl snowflake.txt

CREATE SCHEMA IF NOT EXISTS gold;

-- ============================================================================
-- DIMENSIONS
-- ============================================================================

DROP TABLE IF EXISTS gold.dim_date;
CREATE TABLE gold.dim_date (
    date_key                  INTEGER        NOT NULL,
    date                      DATE           NOT NULL,
    day                       SMALLINT       NOT NULL,
    week                      SMALLINT       NOT NULL,
    month                     SMALLINT       NOT NULL,
    quarter                   SMALLINT       NOT NULL,
    year                      SMALLINT       NOT NULL,
    fiscal_year               SMALLINT       NOT NULL,
    fiscal_quarter            SMALLINT       NOT NULL,
    is_weekend_flag           BOOLEAN        NOT NULL,
    business_day_flag         BOOLEAN        NOT NULL,
    holiday_flag              BOOLEAN        NOT NULL DEFAULT FALSE,
    PRIMARY KEY (date_key)
);

DROP TABLE IF EXISTS gold.dim_airline;
CREATE TABLE gold.dim_airline (
    airline_key                INTEGER        AUTOINCREMENT START 1 INCREMENT 1,
    airline_code               VARCHAR(20)    NOT NULL,
    airline_name               VARCHAR(200)   NOT NULL,
    country                    VARCHAR(100),
    alliance                   VARCHAR(100),
    carrier_type               VARCHAR(50),
    active_flag                BOOLEAN        NOT NULL DEFAULT TRUE,
    source_system              VARCHAR(100),
    dw_created_ts              TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    dw_updated_ts              TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (airline_key)
);

DROP TABLE IF EXISTS gold.dim_aircraft;
CREATE TABLE gold.dim_aircraft (
    aircraft_key               INTEGER        AUTOINCREMENT START 1 INCREMENT 1,
    tail_number                VARCHAR(20)    NOT NULL,
    aircraft_type              VARCHAR(100),
    manufacturer               VARCHAR(100),
    delivery_year              SMALLINT,
    retirement_year            SMALLINT,
    operator_airline_key       INTEGER,
    effective_start_date       DATE           NOT NULL,
    effective_end_date         DATE,
    is_current_flag            BOOLEAN        NOT NULL DEFAULT TRUE,
    source_system              VARCHAR(100),
    dw_created_ts              TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    dw_updated_ts              TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (aircraft_key),
    FOREIGN KEY (operator_airline_key) REFERENCES gold.dim_airline (airline_key)
);

DROP TABLE IF EXISTS gold.dim_event_type;
CREATE TABLE gold.dim_event_type (
    event_type_key             INTEGER        AUTOINCREMENT START 1 INCREMENT 1,
    event_type_name            VARCHAR(200)   NOT NULL,
    event_category             VARCHAR(100),
    description                VARCHAR(1000),
    source_system              VARCHAR(100),
    dw_created_ts              TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    dw_updated_ts              TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (event_type_key)
);

DROP TABLE IF EXISTS gold.dim_airport;
CREATE TABLE gold.dim_airport (
    airport_key                INTEGER        AUTOINCREMENT START 1 INCREMENT 1,
    airport_code               VARCHAR(20)    NOT NULL,
    airport_name               VARCHAR(200),
    city                       VARCHAR(100),
    country                    VARCHAR(100),
    region                     VARCHAR(100),
    iata_code                  VARCHAR(10),
    icao_code                  VARCHAR(10),
    latitude                   NUMBER(9,6),
    longitude                  NUMBER(9,6),
    timezone                   VARCHAR(50),
    source_system              VARCHAR(100),
    dw_created_ts              TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    dw_updated_ts              TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (airport_key)
);

DROP TABLE IF EXISTS gold.dim_route;
CREATE TABLE gold.dim_route (
    route_key                  INTEGER        AUTOINCREMENT START 1 INCREMENT 1,
    origin_airport_key         INTEGER,
    destination_airport_key    INTEGER,
    route_distance_miles       NUMBER(10,2),
    region                     VARCHAR(100),
    route_type                 VARCHAR(50),
    domestic_international     VARCHAR(20),
    source_system              VARCHAR(100),
    dw_created_ts              TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    dw_updated_ts              TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (route_key),
    FOREIGN KEY (origin_airport_key) REFERENCES gold.dim_airport (airport_key),
    FOREIGN KEY (destination_airport_key) REFERENCES gold.dim_airport (airport_key)
);

DROP TABLE IF EXISTS gold.dim_customer;
CREATE TABLE gold.dim_customer (
    customer_key               INTEGER        AUTOINCREMENT START 1 INCREMENT 1,
    customer_name              VARCHAR(200)   NOT NULL,
    customer_type              VARCHAR(50),
    country                    VARCHAR(100),
    segment                    VARCHAR(100),
    active_flag                BOOLEAN        NOT NULL DEFAULT TRUE,
    source_system              VARCHAR(100),
    dw_created_ts              TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    dw_updated_ts              TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (customer_key)
);

DROP TABLE IF EXISTS gold.dim_data_product;
CREATE TABLE gold.dim_data_product (
    product_key                INTEGER        AUTOINCREMENT START 1 INCREMENT 1,
    product_name               VARCHAR(200)   NOT NULL,
    domain                     VARCHAR(100),
    delivery_type              VARCHAR(50),
    description                VARCHAR(1000),
    active_flag                BOOLEAN        NOT NULL DEFAULT TRUE,
    source_system              VARCHAR(100),
    dw_created_ts              TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    dw_updated_ts              TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (product_key)
);

-- ============================================================================
-- FACTS
-- ============================================================================

DROP TABLE IF EXISTS gold.fact_flight_operations;
CREATE TABLE gold.fact_flight_operations (
    flight_key                  BIGINT         AUTOINCREMENT START 1 INCREMENT 1,
    date_key                    INTEGER        NOT NULL,
    airline_key                 INTEGER,
    aircraft_key                INTEGER,
    route_key                   INTEGER,
    origin_airport_key          INTEGER,
    destination_airport_key     INTEGER,
    schedule_id                 VARCHAR(50),
    scheduled_departure_ts      TIMESTAMP,
    actual_departure_ts         TIMESTAMP,
    scheduled_arrival_ts        TIMESTAMP,
    actual_arrival_ts           TIMESTAMP,
    delay_minutes               INTEGER,
    taxi_out_minutes            INTEGER,
    taxi_in_minutes             INTEGER,
    flight_distance_miles       NUMBER(10,2),
    block_hours                 NUMBER(6,2),
    cancelled_flag              BOOLEAN        NOT NULL DEFAULT FALSE,
    diverted_flag               BOOLEAN        NOT NULL DEFAULT FALSE,
    source_system               VARCHAR(100),
    dw_created_ts               TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    dw_updated_ts               TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (flight_key),
    FOREIGN KEY (date_key) REFERENCES gold.dim_date (date_key),
    FOREIGN KEY (airline_key) REFERENCES gold.dim_airline (airline_key),
    FOREIGN KEY (aircraft_key) REFERENCES gold.dim_aircraft (aircraft_key),
    FOREIGN KEY (route_key) REFERENCES gold.dim_route (route_key),
    FOREIGN KEY (origin_airport_key) REFERENCES gold.dim_airport (airport_key),
    FOREIGN KEY (destination_airport_key) REFERENCES gold.dim_airport (airport_key)
);

DROP TABLE IF EXISTS gold.fact_flight_events;
CREATE TABLE gold.fact_flight_events (
    event_key                   BIGINT         AUTOINCREMENT START 1 INCREMENT 1,
    flight_key                  BIGINT,
    event_type_key              INTEGER,
    date_key                    INTEGER        NOT NULL,
    event_timestamp             TIMESTAMP,
    producer_system             VARCHAR(100),
    consumer_system             VARCHAR(100),
    message_size_bytes          INTEGER,
    event_count                 INTEGER,
    source_system               VARCHAR(100),
    dw_created_ts               TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    dw_updated_ts               TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (event_key),
    FOREIGN KEY (flight_key) REFERENCES gold.fact_flight_operations (flight_key),
    FOREIGN KEY (event_type_key) REFERENCES gold.dim_event_type (event_type_key),
    FOREIGN KEY (date_key) REFERENCES gold.dim_date (date_key)
);

DROP TABLE IF EXISTS gold.fact_aircraft_utilization;
CREATE TABLE gold.fact_aircraft_utilization (
    utilization_key             BIGINT         AUTOINCREMENT START 1 INCREMENT 1,
    date_key                    INTEGER        NOT NULL,
    aircraft_key                INTEGER,
    operator_airline_key        INTEGER,
    flight_count                INTEGER        NOT NULL DEFAULT 0,
    utilization_hours           NUMBER(10,2),
    ground_hours                NUMBER(10,2),
    maintenance_hours           NUMBER(10,2),
    available_hours             NUMBER(10,2),
    total_labor_hours           NUMBER(10,2),
    total_parts_used            INTEGER,
    total_discrepancies         INTEGER,
    average_delay_minutes       NUMBER(10,2),
    source_system               VARCHAR(100),
    dw_created_ts               TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    dw_updated_ts               TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (utilization_key),
    FOREIGN KEY (date_key) REFERENCES gold.dim_date (date_key),
    FOREIGN KEY (aircraft_key) REFERENCES gold.dim_aircraft (aircraft_key),
    FOREIGN KEY (operator_airline_key) REFERENCES gold.dim_airline (airline_key)
);

DROP TABLE IF EXISTS gold.fact_route_performance;
CREATE TABLE gold.fact_route_performance (
    route_perf_key              BIGINT         AUTOINCREMENT START 1 INCREMENT 1,
    date_key                    INTEGER        NOT NULL,
    route_key                   INTEGER,
    flight_count                INTEGER        NOT NULL DEFAULT 0,
    delay_count                 INTEGER        NOT NULL DEFAULT 0,
    cancel_count                INTEGER        NOT NULL DEFAULT 0,
    avg_delay_minutes           NUMBER(10,2),
    otp_percentage              NUMBER(5,2),
    source_system               VARCHAR(100),
    dw_created_ts               TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    dw_updated_ts               TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (route_perf_key),
    FOREIGN KEY (date_key) REFERENCES gold.dim_date (date_key),
    FOREIGN KEY (route_key) REFERENCES gold.dim_route (route_key)
);

DROP TABLE IF EXISTS gold.fact_flight_history;
CREATE TABLE gold.fact_flight_history (
    history_key                 BIGINT         AUTOINCREMENT START 1 INCREMENT 1,
    flight_key                  BIGINT,
    airline_key                 INTEGER,
    route_key                   INTEGER,
    date_key                    INTEGER        NOT NULL,
    delay_minutes               INTEGER,
    cancelled_flag              BOOLEAN        NOT NULL DEFAULT FALSE,
    load_factor                 NUMBER(5,2),
    data_source                 VARCHAR(100),
    dw_created_ts               TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    dw_updated_ts               TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (history_key),
    FOREIGN KEY (flight_key) REFERENCES gold.fact_flight_operations (flight_key),
    FOREIGN KEY (airline_key) REFERENCES gold.dim_airline (airline_key),
    FOREIGN KEY (route_key) REFERENCES gold.dim_route (route_key),
    FOREIGN KEY (date_key) REFERENCES gold.dim_date (date_key)
);

DROP TABLE IF EXISTS gold.fact_product_subscriptions;
CREATE TABLE gold.fact_product_subscriptions (
    subscription_key            BIGINT         AUTOINCREMENT START 1 INCREMENT 1,
    customer_key                INTEGER,
    product_key                 INTEGER,
    start_date                  DATE,
    end_date                    DATE,
    subscription_tier           VARCHAR(50),
    subscription_status         VARCHAR(50),
    source_system               VARCHAR(100),
    dw_created_ts               TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    dw_updated_ts               TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (subscription_key),
    FOREIGN KEY (customer_key) REFERENCES gold.dim_customer (customer_key),
    FOREIGN KEY (product_key) REFERENCES gold.dim_data_product (product_key)
);
