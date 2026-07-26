-- Most frequent rejected flows in an exact time range.

SELECT
    account_id,
    vpc_id,
    srcaddr,
    dstaddr,
    dstport,
    protocol,
    COUNT(*) AS reject_count,
    SUM(packets) AS rejected_packets,
    MIN(from_unixtime("start")) AS first_seen,
    MAX(from_unixtime("end")) AS last_seen
FROM "{{database}}"."flow_logs"
WHERE ({{partition_predicate}})
  AND "start" < {{window_end_epoch}}
  AND "end" >= {{window_start_epoch}}
  AND action = 'REJECT'
GROUP BY account_id, vpc_id, srcaddr, dstaddr, dstport, protocol
ORDER BY reject_count DESC
LIMIT 100;
