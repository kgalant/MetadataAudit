String sch = '0 15 * * * ?';
String jobID = system.schedule('Metadata Audit', sch, new MetadataAuditSchedulable());