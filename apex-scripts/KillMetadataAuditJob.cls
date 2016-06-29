Id detailId = [SELECT Id FROM CronJobDetail WHERE Name='Metadata Audit'][0].Id;
if (detailId != null) {
	Id jobId = [SELECT Id from CronTrigger WHERE CronJobDetailId = :detailId][0].Id;
	System.abortJob(jobId);
} 