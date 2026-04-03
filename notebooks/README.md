# Notebooks

PySpark/Fabric notebooks are not used in this platform.

See ADR-008: all data transformation logic is implemented in SQL views and
stored procedures within the Fabric SQL Database. Notebooks introduce a Python
dependency and a Spark execution environment that is not justified for this
workload profile (monthly KPI data, sub-million-row volumes).

This folder is reserved. If a future analytics requirement (bulk historical
processing, ML feature engineering) justifies Spark, notebooks will be added
here with a corresponding ADR update.
