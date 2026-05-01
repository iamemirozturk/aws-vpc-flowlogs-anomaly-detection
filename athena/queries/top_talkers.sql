-- =============================================================================
-- top_talkers.sql
-- Top 50 instance/src/dst pairs by bytes transferred (last 24h)
-- Replace year/month/day values or parameterize via Lambda.
-- =============================================================================

SELECT
    account_id,
    instance_id,
    vpc_id,
    subnet_id,
    srcaddr,
    dstaddr,
    SUM(bytes)                   AS total_bytes,
    ROUND(SUM(bytes) / 1.074e9, 2) AS total_gb,
    SUM(packets)                 AS total_packets,
    COUNT(*)                     AS flow_count,
    MIN(from_unixtime(start))    AS first_seen,
    MAX(from_unixtime(end))      AS last_seen
FROM "{{database}}"."flow_logs"
WHERE year  = '{{year}}'
  AND month = '{{month}}'
  AND day   = '{{day}}'
  AND action = 'ACCEPT'
  AND bytes IS NOT NULL
GROUP BY account_id, instance_id, vpc_id, subnet_id, srcaddr, dstaddr
ORDER BY total_bytes DESC
LIMIT 50;
