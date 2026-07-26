-- Potential data exfiltration by source entity in an exact time window.
-- Replace every {{placeholder}} before running. partition_predicate must include
-- year/month/day/hour clauses for every hour touched by the window.

WITH normalized AS (
    SELECT
        account_id,
        COALESCE(NULLIF(instance_id, '-'), 'unknown') AS instance_id,
        COALESCE(NULLIF(pkt_srcaddr, '-'), srcaddr) AS source_ip,
        COALESCE(NULLIF(pkt_dstaddr, '-'), dstaddr) AS destination_ip,
        bytes,
        packets
    FROM "{{database}}"."flow_logs"
    WHERE ({{partition_predicate}})
      AND "end" >= {{window_start_epoch}}
      AND "end" < {{window_end_epoch}}
      AND action = 'ACCEPT'
      AND flow_direction = 'egress'
      AND log_status = 'OK'
),
destination_totals AS (
    SELECT
        account_id,
        instance_id,
        source_ip,
        destination_ip,
        SUM(bytes) AS destination_bytes,
        SUM(packets) AS destination_packets,
        COUNT(*) AS destination_records
    FROM normalized
    WHERE TRY_CAST(destination_ip AS IPADDRESS) IS NOT NULL
      AND NOT (
        contains(CAST('10.0.0.0/8' AS IPPREFIX), TRY_CAST(destination_ip AS IPADDRESS))
        OR contains(CAST('0.0.0.0/8' AS IPPREFIX), TRY_CAST(destination_ip AS IPADDRESS))
        OR contains(CAST('100.64.0.0/10' AS IPPREFIX), TRY_CAST(destination_ip AS IPADDRESS))
        OR contains(CAST('172.16.0.0/12' AS IPPREFIX), TRY_CAST(destination_ip AS IPADDRESS))
        OR contains(CAST('192.168.0.0/16' AS IPPREFIX), TRY_CAST(destination_ip AS IPADDRESS))
        OR contains(CAST('127.0.0.0/8' AS IPPREFIX), TRY_CAST(destination_ip AS IPADDRESS))
        OR contains(CAST('169.254.0.0/16' AS IPPREFIX), TRY_CAST(destination_ip AS IPADDRESS))
        OR contains(CAST('224.0.0.0/4' AS IPPREFIX), TRY_CAST(destination_ip AS IPADDRESS))
        OR contains(CAST('::1/128' AS IPPREFIX), TRY_CAST(destination_ip AS IPADDRESS))
        OR contains(CAST('fc00::/7' AS IPPREFIX), TRY_CAST(destination_ip AS IPADDRESS))
        OR contains(CAST('fe80::/10' AS IPPREFIX), TRY_CAST(destination_ip AS IPADDRESS))
        OR contains(CAST('ff00::/8' AS IPPREFIX), TRY_CAST(destination_ip AS IPADDRESS))
      )
    GROUP BY account_id, instance_id, source_ip, destination_ip
)
SELECT
    account_id,
    instance_id,
    source_ip,
    max_by(destination_ip, destination_bytes) AS top_destination_ip,
    COUNT(*) AS unique_destinations,
    SUM(destination_bytes) AS total_bytes,
    ROUND(SUM(destination_bytes) / 1073741824.0, 2) AS total_gib,
    SUM(destination_packets) AS total_packets,
    SUM(destination_records) AS flow_records
FROM destination_totals
GROUP BY account_id, instance_id, source_ip
HAVING SUM(destination_bytes) > {{threshold_bytes}}
ORDER BY total_bytes DESC
LIMIT {{max_findings}};
