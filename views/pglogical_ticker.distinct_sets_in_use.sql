CREATE OR REPLACE VIEW pglogical_ticker.distinct_sets_in_use AS
SELECT DISTINCT rs.set_name, rs.set_id
FROM pglogical.replication_set rs
INNER JOIN pglogical.node n ON n.node_id = rs.set_nodeid
INNER JOIN pglogical.node_interface ni ON ni.if_nodeid = n.node_id
WHERE EXISTS (SELECT 1
  FROM pglogical_ticker.rep_set_table_wrapper() rsr
  WHERE rsr.set_id = rs.set_id)
ORDER BY rs.set_name;
