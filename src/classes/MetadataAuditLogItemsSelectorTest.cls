@isTest
private class MetadataAuditLogItemsSelectorTest
{
	@isTest
	static void testGetSObjectFieldList()
	{
		List<Schema.SObjectField> fields = new MetadataAuditLogItemsSelector().getSObjectFieldList();
		System.assert(fields.size() > 0, '0 Fields returned, something is wrong...');
	}

	@isTest
	static void testGetSObjectType()
	{
		Schema.SObjectType myType = new MetadataAuditLogItemsSelector().getSObjectType();
		System.assertEquals(myType, Metadata_Audit_Log_Item__c.sObjectType, '0 Fields returned, something is wrong...');
	}

	@isTest
	static void testSelectById()
	{
		Set<Id> itemIDs = setupTestData();
		List<Metadata_Audit_Log_Item__c> items = new MetadataAuditLogItemsSelector().selectById(itemIDs);
		System.assertEquals(3, items.size(), '3 items expected to be returned, got ' + items.size() + ', something is wrong...');

	}

	@isTest
	static void testSelectExistingByTypeOldestFirst()
	{
		Set<Id> itemIDs = setupTestData();
		List<Metadata_Audit_Log_Item__c> items = new MetadataAuditLogItemsSelector().selectExistingByTypeOldestFirst('ApexClass');
		System.assertEquals(3, items.size(), '3 items expected to be returned, got ' + items.size() + ', something is wrong...');
		Metadata_Audit_Log_Item__c item1 = items[0];
		System.assertEquals('OldestClass', item1.Name, 'Expected oldest class to be OldestClass, got: ' + item1.name + ', something is wrong...');
		item1 = items[1];
		System.assertEquals('MiddleClass', item1.Name, 'Expected second oldest class to be MiddleClass, got: ' + item1.name + ', something is wrong...');
		item1 = items[2];
		System.assertEquals('NewestClass', item1.Name, 'Expected oldest class to be NewestClass, got: ' + item1.name + ', something is wrong...');

	}

	static Set<Id> setupTestData() {

		Metadata_Audit_Job_Log__c myJobLog = new Metadata_Audit_Job_Log__c();
		insert myJobLog;

		Metadata_Audit_Run_Log__c myRunLog = new Metadata_Audit_Run_Log__c();
		myRunLog.Metadata_category__c = 'ApexClass';
		myRunLog.Items_added__c = 3;
		myRunLog.Items_modified__c = 0;
		myRunLog.Items_deleted__c = 0;
		myRunLog.Number_of_query_items_returned__c = 3;
		myRunLog.Metadata_Audit_Job_Log__c = myJobLog.Id;
		insert myRunLog;
		
		Set<Id> itemIDs = new Set<Id>();

		Metadata_Audit_Log_Item__c newItem1 = new Metadata_Audit_Log_Item__c();
		newItem1.Type__c = 'ApexClass';
		newItem1.Entry_type__c = 'Initial create';
		newItem1.Metadata_Item_ID__c = '01p28000003NBffAAG';
		newItem1.Name = 'MiddleClass';
		newItem1.Metadata_LM_Date__c = DateTime.newInstance(2016, 12, 02, 3, 3, 3);
		newItem1.Metadata_Audit_Run_Log__c = myRunLog.Id; 
		newItem1.Metadata_Created_By__c = 'SomeUser'; 
		newItem1.Metadata_Created_Date__c = DateTime.newInstance(2016, 12, 01, 3, 3, 3);
		insert newItem1;
		itemIDs.add(newItem1.Id);
		Metadata_Audit_Log_Item__c newItem2 = new Metadata_Audit_Log_Item__c();
		newItem2.Type__c = 'ApexClass';
		newItem2.Entry_type__c = 'Initial create';
		newItem2.Metadata_Item_ID__c = '01p28000003NBfgAAG';
		newItem2.Name = 'NewestClass';
		newItem2.Metadata_LM_Date__c = DateTime.newInstance(2016, 12, 03, 3, 3, 3);
		newItem2.Metadata_Audit_Run_Log__c = myRunLog.Id; 
		newItem2.Metadata_Created_By__c = 'SomeUser'; 
		newItem2.Metadata_Created_Date__c = DateTime.newInstance(2016, 12, 01, 3, 3, 3);
		insert newItem2;
		itemIDs.add(newItem2.Id);
		Metadata_Audit_Log_Item__c newItem3 = new Metadata_Audit_Log_Item__c();
		newItem3.Type__c = 'ApexClass';
		newItem3.Entry_type__c = 'Initial create';
		newItem3.Metadata_Item_ID__c = '01p28000003NBfhAAG';
		newItem3.Name = 'OldestClass';
		newItem3.Metadata_LM_Date__c = DateTime.newInstance(2016, 12, 01, 3, 3, 3);
		newItem3.Metadata_Audit_Run_Log__c = myRunLog.Id; 
		newItem3.Metadata_Created_By__c = 'SomeUser'; 
		newItem3.Metadata_Created_Date__c = DateTime.newInstance(2016, 12, 01, 3, 3, 3);
		insert newItem3;
		itemIDs.add(newItem3.Id);
		return itemIDs;
	}
}