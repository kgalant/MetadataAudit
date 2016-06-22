/**
 * See https://github.com/financialforcedev/fflib-apex-common for more info
 *
 * Install library via 
 *   https://githubsfdeploy.herokuapp.com/app/githubdeploy/financialforcedev/fflib-apex-common
 */

/**
 * Class encapsulates query logic for Metadata_Audit_Job_Log__c
 *
 * https://developer.salesforce.com/page/Apex_Enterprise_Patterns_-_Selector_Layer
 **/
public class MetadataAuditJobLogSelector extends fflib_SObjectSelector
{
	public List<Schema.SObjectField> getSObjectFieldList()
	{
		return new List<Schema.SObjectField> {
				Metadata_Audit_Job_Log__c.Id,
				Metadata_Audit_Job_Log__c.Name,
				Metadata_Audit_Job_Log__c.Execution_Log__c
			};
	}

	public Schema.SObjectType getSObjectType()
	{
		return Metadata_Audit_Job_Log__c.sObjectType;
	}

	public List<Metadata_Audit_Job_Log__c> selectById(Set<ID> idSet)
	{
		return (List<Metadata_Audit_Job_Log__c>) selectSObjectsById(idSet);
	}	
}