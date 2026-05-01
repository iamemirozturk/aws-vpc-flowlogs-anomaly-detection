-- =============================================================================
-- exfil_detection.sql
-- Identifies outbound transfers exceeding threshold to non-RFC-1918 destinations.
-- Run via Lambda or manually in the Athena console.
-- =============================================================================

SELECT
    account_id,
    instance_id,
    vpc_id,
    srcaddr,
    dstaddr,
    pkt_src_aws_service,
    pkt_dst_aws_service,
    flow_direction,
    SUM(bytes)                     AS total_bytes,
    ROUND(SUM(bytes) / 1.074e9, 2) AS total_gb,
    SUM(packets)                   AS total_packets,
    COUNT(*)                       AS flow_records,
    MIN(from_unixtime(start))      AS window_start,
    MAX(from_unixtime(end))        AS window_end
FROM "{{database}}"."flow_logs"
WHERE year  = '{{year}}'
  AND month = '{{month}}'
  AND day   = '{{day}}'
  AND action = 'ACCEPT'
  AND flow_direction = 'egress'
  -- Exclude private ranges
  AND regexp_like(dstaddr, '^(?!10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.|169\.254\.).*')
GROUP BY
    account_id, instance_id, vpc_id, srcaddr, dstaddr,
    pkt_src_aws_service, pkt_dst_aws_service, flow_direction
HAVING SUM(bytes) > {{threshold_bytes}}
ORDER BY total_bytes DESC;
