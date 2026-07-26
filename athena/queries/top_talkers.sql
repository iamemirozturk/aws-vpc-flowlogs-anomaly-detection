-- Top source/destination pairs in an exact time range.
-- partition_predicate must cover each year/month/day/hour touched by the range.

SELECT
    account_id,
    instance_id,
    vpc_id,
    subnet_id,
    COALESCE(NULLIF(pkt_srcaddr, '-'), srcaddr) AS source_ip,
    COALESCE(NULLIF(pkt_dstaddr, '-'), dstaddr) AS destination_ip,
    SUM(bytes) AS total_bytes,
    ROUND(SUM(bytes) / 1073741824.0, 2) AS total_gib,
    SUM(packets) AS total_packets,
    COUNT(*) AS flow_count,
    MIN(from_unixtime("start")) AS first_seen,
    MAX(from_unixtime("end")) AS last_seen
FROM "{{database}}"."flow_logs"
WHERE ({{partition_predicate}})
  AND "end" >= {{window_start_epoch}}
  AND "end" < {{window_end_epoch}}
  AND action = 'ACCEPT'
  AND bytes IS NOT NULL
GROUP BY
    account_id,
    instance_id,
    vpc_id,
    subnet_id,
    COALESCE(NULLIF(pkt_srcaddr, '-'), srcaddr),
    COALESCE(NULLIF(pkt_dstaddr, '-'), dstaddr)
ORDER BY total_bytes DESC
LIMIT 50;
