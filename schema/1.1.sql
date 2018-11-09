--This must be done AFTER we update the function def
SELECT pglogical_ticker.drop_ext_object('FUNCTION','pglogical_ticker.dependency_update()');
DROP FUNCTION pglogical_ticker.dependency_update();
SELECT pglogical_ticker.drop_ext_object('VIEW','pglogical_ticker.rep_set_table_wrapper');
DROP VIEW IF EXISTS pglogical_ticker.rep_set_table_wrapper; 
