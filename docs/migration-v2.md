# Upgrade notes

The original repository was not a valid Terraform configuration and its single
root could not select different credentials for each spoke. Treat this release
as an architectural migration.

Expected changes include independent spoke states, removal of the invalid S3
delivery role and Glue crawler, an explicit projected table, detector KMS/state/
DLQ/alarms, and changed bucket ownership/policies/lifecycle.

1. Back up state and inventory every deployed resource.
2. Test the corrected central root in a non-production account.
3. Import an existing evidence bucket and related resources one at a time; never
   accept an accidental replacement.
4. Create one spoke backend per account/Region.
5. Move state with explicit source/destination state files or import Flow Log
   IDs. Test commands on copied state and peer review them.
6. Confirm delivery and schema before removing crawler resources.
7. Test subscription, replay idempotency, DLQ, and alarms.
8. Remove obsolete roles only after access analysis shows no remaining use.

Object Lock cannot be disabled on an existing bucket. The guide does not publish
universal `state mv` commands because actual old state addresses must be
inspected and the original root could not successfully plan as written.
