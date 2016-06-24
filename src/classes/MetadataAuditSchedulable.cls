/*
String sch = '0 15 * * * ?';
String jobID = system.schedule('Metadata Audit', sch, new MetadataAuditSchedulable());
*/

global class MetadataAuditSchedulable implements Schedulable {
	global void execute(SchedulableContext sc) {
		System.enqueueJob(new MetadataAuditLogQueueable());
	}
}