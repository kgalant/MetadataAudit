public class MetadataAuditLogQueueable implements Queueable, Database.AllowsCallouts {
	public void execute(QueueableContext context) {
		Metadata_Audit_Configuration__mdt[] myMDTs = 
		[select QualifiedApiName from Metadata_Audit_Configuration__mdt ORDER BY QualifiedApiName];

		MetadataAuditSettings__c settings = MetadataAuditSettings__c.getValues('Automated');
		String lastRunMdType = settings.LastRunMetadataType__c;

		// if lastrun is blank, start from the top of the Custom MDTs
		// if not blank, find the one that last ran, and run the one after

		boolean didSomething = false;
		boolean runNext = lastRunMdType == null || lastRunMdType.length() == 0 ? true : false;
		Integer runCount = 0;
		System.debug(LoggingLevel.ERROR, 'Last run: ' + settings.LastRunMetadataType__c);
		for (Metadata_Audit_Configuration__mdt mymdt : myMDTs) {
			System.debug(LoggingLevel.DEBUG, 'Looking at MDT: ' + myMDT);
			if (mymdt.QualifiedApiName == lastRunMdType) {
				runNext = true;
			} else if (runNext == true) {
				System.debug(LoggingLevel.ERROR, 'Will run metadata audit for ' + mymdt.QualifiedApiName);
				settings.LastRunMetadataType__c = mymdt.QualifiedApiName;
				MetadataAuditLogService.fetchAndProcessType(mymdt.QualifiedApiName);
				runCount++;
				runNext = false;
				didSomething = true;
				upsert settings;
				System.debug(LoggingLevel.ERROR, 'Completed metadata audit for ' + mymdt.QualifiedApiName);
				break;
			}
			
		}

		// if we reach here with runNext set, it means that the last job ran the last configged item
		// so just reset the lastRun field

		if (runNext == true) {
			settings.LastRunMetadataType__c = null;
			upsert settings;
			System.debug(LoggingLevel.DEBUG, 'Completed execution of all config items. Resetting counter (LastRunMetadataType__c).');
		}

		// if we did do something in this batch, fire off one more

		if (didSomething && runCount < 5) {
			FutureChaining();
		}
		System.debug(LoggingLevel.DEBUG, 'Completed MetadataAuditLogQueueable execution.');

		

	}

	@future(callout=true)
    public static void FutureChaining() {

       System.debug(LoggingLevel.DEBUG, 'Will add another job to queue.');
		System.enqueueJob(new MetadataAuditLogQueueable());
    }
}