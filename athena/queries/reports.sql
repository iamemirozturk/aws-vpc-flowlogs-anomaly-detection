-- =============================================================================
-- cross_account_summary.sql
-- Monthly bandwidth summary broken down by account and VPC.
-- =============================================================================

SELECT
    account_id,
    vpc_id,
    action,
    SUM(bytes)                          AS total_bytes,
    ROUND(SUM(bytes) / 1.074e9, 2)     AS total_gb,
    ROUND(SUM(bytes) / 1.100e12, 4)    AS total_tb,
    SUM(packets)                        AS total_packets,
    COUNT(DISTINCT instance_id)         AS unique_instances,
    COUNT(DISTINCT srcaddr)             AS unique_src_ips,
    COUNT(DISTINCT dstaddr)             AS unique_dst_ips,
    COUNT(*)                            AS total_flow_records
FROM "{{database}}"."flow_logs"
WHERE year  = '{{year}}'
  AND month = '{{month}}'
GROUP BY account_id, vpc_id, action
ORDER BY account_id, total_bytes DESC;


-- =============================================================================
-- instance_traffic_report.sql
-- Detailed traffic breakdown for a specific instance over a date range.
-- =============================================================================

SELECT
    DATE(from_unixtime(start))         AS traffic_date,
    srcaddr,
    dstaddr,
    srcport,
    dstport,
    protocol,
    action,
    SUM(bytes)                         AS total_bytes,
    ROUND(SUM(bytes) / 1.074e9, 2)    AS total_gb,
    SUM(packets)                       AS total_packets,
    COUNT(*)                           AS flow_records
FROM "{{database}}"."flow_logs"
WHERE year   = '{{year}}'
  AND month  = '{{month}}'
  AND instance_id = '{{instance_id}}'
GROUP BY
    DATE(from_unixtime(start)), srcaddr, dstaddr, srcport, dstport, protocol, action
ORDER BY traffic_date DESC, total_bytes DESC;


-- =============================================================================
-- rejected_traffic_hotspots.sql
-- Top REJECT events — useful for firewall tuning and intrusion detection.
-- =============================================================================

SELECT
    account_id,
    vpc_id,
    srcaddr,
    dstaddr,
    dstport,
    protocol,
    COUNT(*)          AS reject_count,
    SUM(packets)      AS rejected_packets,
    MIN(from_unixtime(start)) AS first_seen,
    MAX(from_unixtime(end))   AS last_seen
FROM "{{database}}"."flow_logs"
WHERE year  = '{{year}}'
  AND month = '{{month}}'
  AND day   = '{{day}}'
  AND action = 'REJECT'
GROUP BY account_id, vpc_id, srcaddr, dstaddr, dstport, protocol
ORDER BY reject_count DESC
LIMIT 100;
