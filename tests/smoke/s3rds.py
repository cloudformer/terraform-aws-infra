"""Smoke test for modules/s3rds, run by `make smoke P=s3rds` against the deployed examples/s3rds.

Not written yet: for now `make smoke` only proves that examples/s3rds applies and destroys cleanly.
To come: connect to db_url with s3rds.pymysql, create / insert / select, and a write on db_ro_url gets 403.
"""
print("smoke s3rds: no checks yet (deploy + destroy only)")
