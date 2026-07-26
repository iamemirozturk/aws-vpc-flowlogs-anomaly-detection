-- Monthly bandwidth summary by account, VPC, and action.

SELECT
    account_id,
    vpc_id,
    action,
    SUM(bytes) AS total_bytes,
    ROUND(SUM(bytes) / 1073741824.0, 2) AS total_gib,
    ROUND(SUM(bytes) / 1099511627776.0, 4) AS total_tib,
    SUM(packets) AS total_packets,
    COUNT(DISTINCT instance_id) AS unique_instances,
    COUNT(DISTINCT srcaddr) AS unique_source_ips,
    COUNT(DISTINCT dstaddr) AS unique_destination_ips,
    COUNT(*) AS flow_records
FROM "{{database}}"."flow_logs"
WHERE "year" = '{{year}}'
  AND "month" = '{{month}}'
GROUP BY account_id, vpc_id, action
ORDER BY account_id, total_bytes DESC;
