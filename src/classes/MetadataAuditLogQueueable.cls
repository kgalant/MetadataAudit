public class MetadataAuditLogQueueable implements Queueable, Database.AllowsCallouts {
	private static Id currentJobId;

	// this is a constructor which is called once we have established a job that all subsequent metadata searches are going to
	// be attached to

	public MetadataAuditLogQueueable(Id jobLogId) {
		currentJobId = jobLogId;
		System.debug(LoggingLevel.DEBUG, 'Job Log Id: ' + currentJobId);
	}

	// this is the default constructor which will establish a job id to tie all subsequent executions together

	public MetadataAuditLogQueueable() {
		
	}

	public void execute(QueueableContext context) {
		Metadata_Audit_Configuration__mdt[] myMDTs = 
		[select QualifiedApiName from Metadata_Audit_Configuration__mdt WHERE Enabled__c=TRUE ORDER BY QualifiedApiName];

		MetadataAuditSettings__c settings = MetadataAuditSettings__c.getValues('Automated');

		if (settings != null) {
			String lastRunMdType = settings.LastRunMetadataType__c;
			Id currentRunId = settings.JobRunId__c;
			if (currentRunId == null) {
				currentJobId = createNewRun();

				// we'll create a new job id, then chain a new execution to run the main stuff, as we couldn't create the 
				// Jog Run log, then do a callout

				settings.JobRunId__c = currentJobId;
				upsert settings;
				FutureChaining();
			} else {
				currentJobId = currentRunId;
			

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
						
						MetadataAuditLogService.fetchAndProcessType(mymdt.QualifiedApiName, currentJobId);
						runCount++;
						runNext = false;
						didSomething = true;
						upsert settings;
						System.debug(LoggingLevel.ERROR, 'Completed metadata audit for ' + mymdt.QualifiedApiName);
						break;
					}
					
				}

				// if we reach here with runNext set, it means that the last job ran the last configged item
				// so just reset the lastRun, joblog fields

				if (runNext == true) {
					doHousekeeping(settings);
				}

				// if we did do something in this batch, fire off one more

				if (didSomething) { // && runCount < 5 - runCount less than 5 for dev orgs only
					FutureChaining();
				}
				System.debug(LoggingLevel.DEBUG, 'Completed MetadataAuditLogQueueable execution.');
			}

		} else {
			System.debug(LoggingLevel.DEBUG, 'Run setup custom settings not found, cannot continue...');
		}
	}

	@future(callout=true)
    public static void FutureChaining() {

       System.debug(LoggingLevel.DEBUG, 'Will add another job to queue.');
		System.enqueueJob(new MetadataAuditLogQueueable(currentJobId));
    }

    // this method creates a new job log for this run (since we apparently don't have one yet), and returns the ID

    private Id createNewRun() {
    	// not worth it engaging the FFLIB here - just create the object and store the ID
		Metadata_Audit_Job_Log__c myJobLog = new Metadata_Audit_Job_Log__c();
		myJobLog.Execution_Log__c = 'Execution started at: ' + Datetime.now();
		myJobLog.Execution_Log__c += '\r\n';
		insert myJobLog;
		currentJobId = myJobLog.id;
		System.debug(LoggingLevel.DEBUG, 'Job Log Id: ' + currentJobId);
		return myJobLog.Id;
    }

    // this methods does all the needed housekeeping after the main job is done
    // so resets counters, etc., but also cleans up the old data

    private static void doHousekeeping(MetadataAuditSettings__c settings) {

    	// reset tracking fields

    	settings.LastRunMetadataType__c = null;
    	settings.JobRunId__c = null;
    	upsert settings;
    	System.debug(LoggingLevel.DEBUG, 'Completed execution of all config items. Resetting counter (LastRunMetadataType__c).');

    	// cleanup data

    	Integer retentionTime = settings.Empty_log_retention_time__c.intValue();

    	if (retentionTime != null && retentionTime > 0) {
    		doDataCleanup(retentionTime);
    	}

    	
    }

    // this method will delete empty log lines older than _retentionTime_ hours

    private static void doDataCleanup(Integer retentionTime) {
    	// clean up empty log lines

    	String query = 'SELECT Id,Metadata_Audit_Job_Log__c,Metadata_category__c, LastModifiedDate ' + 
    		' FROM Metadata_Audit_Run_Log__c WHERE Items_added__c = 0 AND Items_deleted__c = 0 AND ' +
    		' Items_modified__c = 0 AND LastModifiedDate < LAST_N_DAYS:' + retentionTime;

    	List<Metadata_Audit_Run_Log__c> marls = Database.query(query);

    	delete marls;
   	}
}