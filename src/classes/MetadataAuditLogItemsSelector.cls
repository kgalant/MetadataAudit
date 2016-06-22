/**
 * See https://github.com/financialforcedev/fflib-apex-common for more info
 *
 * Install library via 
 *   https://githubsfdeploy.herokuapp.com/app/githubdeploy/financialforcedev/fflib-apex-common
 */

/**
 * Class encapsulates query logic for Metadata_Audit_Log_Item__c
 *
 * https://developer.salesforce.com/page/Apex_Enterprise_Patterns_-_Selector_Layer
 **/
public class MetadataAuditLogItemsSelector extends fflib_SObjectSelector
{
	public List<Schema.SObjectField> getSObjectFieldList()
	{
		return new List<Schema.SObjectField> {
				Metadata_Audit_Log_Item__c.Id,
				Metadata_Audit_Log_Item__c.Type__c,
				Metadata_Audit_Log_Item__c.Entry_type__c,
				Metadata_Audit_Log_Item__c.Metadata_Created_By__c,
				Metadata_Audit_Log_Item__c.Metadata_Created_Date__c,
				Metadata_Audit_Log_Item__c.Metadata_Item_ID__c,
				Metadata_Audit_Log_Item__c.Metadata_LM_By__c,
	        	Metadata_Audit_Log_Item__c.Metadata_LM_Date__c,
	        	Metadata_Audit_Log_Item__c.Name,
	        	Metadata_Audit_Log_Item__c.Filename__c
			};
	}

	public Schema.SObjectType getSObjectType()
	{
		return Metadata_Audit_Log_Item__c.sObjectType;
	}

	public List<Metadata_Audit_Log_Item__c> selectById(Set<ID> idSet)
	{
		return (List<Metadata_Audit_Log_Item__c>) selectSObjectsById(idSet);
	}

	public List<Metadata_Audit_Log_Item__c> selectExistingByTypeOldestFirst(String typeName) {
		assertIsAccessible();
		return (List<Metadata_Audit_Log_Item__c>) Database.query(
				String.format(
				'select {0} ' +
				  'from {1} ' +
				  'where Type__c = :typename ' + 
				  'order by Metadata_LM_Date__c',
				new List<String> {
					getFieldListString(),
					getSObjectName() } ) );
	}

	
}