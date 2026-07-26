-- Traffic report for one instance over an exact time range.

SELECT
    DATE(from_unixtime("start")) AS traffic_date,
    srcaddr,
    dstaddr,
    srcport,
    dstport,
    protocol,
    action,
    SUM(bytes) AS total_bytes,
    ROUND(SUM(bytes) / 1073741824.0, 2) AS total_gib,
    SUM(packets) AS total_packets,
    COUNT(*) AS flow_records
FROM "{{database}}"."flow_logs"
WHERE ({{partition_predicate}})
  AND "end" >= {{window_start_epoch}}
  AND "end" < {{window_end_epoch}}
  AND instance_id = '{{instance_id}}'
GROUP BY
    DATE(from_unixtime("start")),
    srcaddr,
    dstaddr,
    srcport,
    dstport,
    protocol,
    action
ORDER BY traffic_date DESC, total_bytes DESC;
