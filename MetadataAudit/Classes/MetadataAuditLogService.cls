/*

	This is the service class which facilitates extracting metadata information from the org into 
	the Metadata_Audit_Log_Item__c object.

	*/

// TODO: Some sort of handling of different API versions?
// TODO: think about whether we want to check whether a metadata type query string is valid

public with sharing class MetadataAuditLogService {

	private static Integer APIVERSION = 36;

	private static String ENTRYTYPE_CREATE = 'Initial create';
	private static String ENTRYTYPE_MOD = 'Modification';
	private static String ENTRYTYPE_DELETE = 'Deletion';

	private static String CUSTOMSETTING_NAME = 'Automated';

	public MetadataAuditLogService() {
		
	}

	public static void fetchAllMetadataFromOrg() {

	}

	public static void fetchAndProcessType(String metadataType) {
		MetadataService.FileProperties[] fp = fetchMetadataTypeFromOrg(metadataType);
		processMetadata(fp, metadataType);
	}
	
	public static MetadataService.FileProperties[] fetchMetadataTypesFromOrg(String[] metadataTypeNames) {

		MetadataService.MetadataPort service = new MetadataService.MetadataPort();

		
		// do the callout to get a sessionid using named credentials

		MetadataAuditSettings__c mySettings = MetadataAuditSettings__c.getInstance(CUSTOMSETTING_NAME);
		System.debug(LoggingLevel.FINE, 'Custom setting with params: ' + mySettings);

		// TODO: test if we did get the custom setting back, if not something is seriously wrong

		HttpRequest request = new HttpRequest();

		request.setEndpoint(mySettings.Endpoint__c);  // sfdc sandbox
		request.setMethod('POST');
		request.setTimeout(60000);

		request.setBody(
		    'grant_type=password' +
		    '&client_id=' + EncodingUtil.urlEncode(mySettings.Consumer_Key__c, 'UTF-8') +
		    '&client_secret=' + EncodingUtil.urlEncode(mySettings.Consumer_Secret__c, 'UTF-8') +
		    '&username=' + EncodingUtil.urlEncode(mySettings.Username__c, 'UTF-8') +
		    '&password=' + EncodingUtil.urlEncode(mySettings.Password__c, 'UTF-8')
		);

		HttpResponse response = new Http().send(request);
		System.debug(response.getBody());

        try {
            OAuth2 oauth2 = (OAuth2) JSON.deserialize(
                response.getBody(),
                MetadataAuditLogService.OAuth2.class
            );
            service.SessionHeader = new MetadataService.SessionHeader_element();
            service.SessionHeader.sessionId = oauth2.access_token;
        } catch(Exception whoops){
                System.debug('OAuthException: ' + whoops.getTypeName() + ': ' + whoops.getMessage());
        }
		
        // TODO: test if we have a valid session - if not, no point in trying to connect just to get errors

		List<MetadataService.ListMetadataQuery> queries = new List<MetadataService.ListMetadataQuery>();
		for (String metadataTypeName : metadataTypeNames) {
			MetadataService.ListMetadataQuery query = new MetadataService.ListMetadataQuery();
			query.type_x = metadataTypeName;
			queries.add(query);
		}
		return service.listMetadata(queries, APIVERSION);	
	}

	public static MetadataService.FileProperties[] fetchMetadataTypeFromOrg(String metadataTypeName) {
		return fetchMetadataTypesFromOrg(new String[] {metadataTypeName});			
	}


	public static void processMetadata(MetadataService.FileProperties[] fpList, String mdType) {

		fflib_SObjectUnitOfWork uow = new fflib_SObjectUnitOfWork(SERVICE_SOBJECTS);

		Metadata_Audit_Run_Log__c runLog = new Metadata_Audit_Run_Log__c();
		runLog.Metadata_category__c = mdType;
		runLog.Number_of_query_items_returned__c = fpList.size();
		runLog.Items_added__c = 0;
		runLog.Items_deleted__c = 0;
		runLog.Items_modified__c = 0;
		uow.registerNew(runLog);

		if (fpList.size() != 0) {
			// get a map by Metadata_Item_ID__c field rather than list
			// will also get rid of duplicate items for us

			MetadataAuditLogItemsSelector maliSelector = new MetadataAuditLogItemsSelector();

			List<Metadata_Audit_Log_Item__c> existingItems = maliSelector.selectExistingByTypeOldestFirst(mdType);
			Map<String,Metadata_Audit_Log_Item__c> existingItemsMap = new Map<String,Metadata_Audit_Log_Item__c>();
			for (Metadata_Audit_Log_Item__c mali : existingItems) {
				if (!existingItemsMap.containsKey(mali.Metadata_Item_ID__c)) {
					// haven't seen this item before, jsut add to map
					existingItemsMap.put(mali.Metadata_Item_ID__c, mali);
					} else {
					// we already have something in the map, check what this new item is and act accordingly
					if (mali.Entry_type__c == ENTRYTYPE_DELETE) {
						// this is a deletion record, so as of this timestamp, this item doesn't exist in the org
						// it may get added back in the future, but then we'll add it back to the map when we see the record
						// so for now, just remove from the map

						existingItemsMap.remove(mali.Metadata_Item_ID__c);
						} else {
						// this is either the initial create or a mod record - so replace the one currently in the map with this one
						existingItemsMap.put(mali.Metadata_Item_ID__c, mali);
					}
				}
			}


			// now process the incoming items and create appropriate records

			Map<String, Metadata_Audit_Log_Item__c> incomingMalis = new Map<String, Metadata_Audit_Log_Item__c>();

			for (MetadataService.FileProperties fp : fpList) {
				System.debug(LoggingLevel.FINE, 'FP: ' + fp);
				Metadata_Audit_Log_Item__c mali = new Metadata_Audit_Log_Item__c();
				mali.Type__c = fp.type_x;
				mali.Metadata_Item_ID__c = ((fp.id == null || fp.id == '') ? fp.fullName : fp.id); // hack for standard object which have no id

				// figure out the entry type - if we have it in existing items, it's a mod, else a create
				if (existingItemsMap.containsKey(mali.Metadata_Item_ID__c)) {
					mali.Entry_type__c = ENTRYTYPE_MOD;
				} else {
					mali.Entry_type__c = ENTRYTYPE_CREATE;
				}

				mali.Metadata_Created_By__c = fp.createdByName;
				mali.Metadata_Created_Date__c = fp.createdDate;
				mali.Metadata_LM_Date__c = fp.lastModifiedDate;
				mali.Metadata_LM_By__c = fp.lastModifiedByName;
				mali.Name = fp.fullName;
				mali.Filename__c = fp.filename;

				System.debug(LoggingLevel.FINE, 'MALI: ' + mali);

				incomingMalis.put(mali.Metadata_Item_ID__c, mali);        	
			}

			// now look through the existing items and see which, if any, didn't have a corresponiding incoming record
			// for those, create a delete record and register with the Unit of Work

			for (Metadata_Audit_Log_Item__c mali : existingItemsMap.values()) {
				if (!incomingMalis.containsKey(mali.Metadata_Item_ID__c)) {
					// we have it in the existing list, but not in the incoming list
					// this must mean it's gotten deleted 
					// create a delete record
					Metadata_Audit_Log_Item__c deleteMali = new Metadata_Audit_Log_Item__c();
					deleteMali.Type__c = mali.Type__c;
					deleteMali.Metadata_Item_ID__c = mali.Metadata_Item_ID__c;
					deleteMali.Entry_type__c = ENTRYTYPE_DELETE;
					deleteMali.Metadata_Created_By__c = mali.Metadata_Created_By__c;
					deleteMali.Metadata_Created_Date__c = mali.Metadata_Created_Date__c;
					deleteMali.Metadata_LM_By__c = mali.Metadata_LM_By__c;
					deleteMali.Metadata_LM_Date__c = mali.Metadata_LM_Date__c;
					deleteMali.Name = mali.Name;
					deleteMali.Filename__c = mali.Filename__c;
					runLog.Items_deleted__c++;
					uow.registerRelationship(deleteMali, Metadata_Audit_Log_Item__c.Metadata_Audit_Run_Log__c, runLog); 
					uow.registerNew(deleteMali);
				}
			}

			// now walk the incoming items and get rid of any where the last modified date is the same as what we have
			// so actually, walk the list and register any where the LM date isn't the same as the existing one

			for (Metadata_Audit_Log_Item__c mali : incomingMalis.values()) {
				Metadata_Audit_Log_Item__c existingMali = existingItemsMap.get(mali.Metadata_Item_ID__c);
				if (existingMali == null || (existingMali != null && mali.Metadata_LM_Date__c != existingMali.Metadata_LM_Date__c)) {
					uow.registerNew(mali);
					uow.registerrelationship(mali, Metadata_Audit_Log_Item__c.Metadata_Audit_Run_Log__c, runLog); 
					if (mali.Entry_type__c == ENTRYTYPE_CREATE) runLog.Items_added__c++; 
					else if (mali.Entry_type__c == ENTRYTYPE_MOD) runLog.Items_modified__c++;
				}
			}
		}
		uow.commitWork();
	}

	private static List<String> METADATA_NAMES = 
	new List<String> { 
		'AccountOwnerSharingRule',
		'AccountCriteriaBasedSharingRule',
		'AccountSharingRules',
		'AccountTerritorySharingRule',
		'AccountTerritorySharingRules',
		'AnalyticSnapshot',
		'AppMenu',
		'CustomApplication',
		'ApprovalProcess',
		'AssignmentRules',
		'AuthProvider',
		'AutoResponseRules',
		'CallCenter',
		'CampaignCriteriaBasedSharingRule',
		'CampaignOwnerSharingRule',
		'CampaignSharingRules',
		'CaseCriteriaBasedSharingRule',
		'CaseOwnerSharingRule',
		'CaseSharingRules',
		'ApexClass',
		'Community',
		'ApexComponent',
		'ConnectedApp',
		'ContactCriteriaBasedSharingRule',
		'ContactOwnerSharingRule',
		'ContactSharingRules',
		'CustomApplicationComponent',
		'CustomObjectCriteriaBasedSharingRule',
		'CustomObjectOwnerSharingRule',
		'CustomObjectSharingRules',
		'Dashboard',
		'DataCategoryGroup',
		'Document',
		'EmailTemplate',
		'EntitlementProcess',
		'EntitlementTemplate',
		'EscalationRules',
		'FlexiPage',
		'Flow',
		'Group',
		'HomePageComponent',
		'HomePageLayout',
		'InstalledPackage',
		'CustomLabels',
		'Layout',
		'LeadCriteriaBasedSharingRule',
		'LeadOwnerSharingRule',
		'LeadSharingRules',
		'Letterhead',
		'MilestoneType',
		'Network',
		'CustomObjectTranslation',
		'CustomField',
		'CustomObject',
		'WebLink',
		'OpportunityCriteriaBasedSharingRule',
		'OpportunityOwnerSharingRule',
		'OpportunitySharingRules',
		'ApexPage',
		'PermissionSet',
		'Portal',
		'PostTemplate',
		'Profile',
		'Queue',
		'QuickAction',
		'RemoteSiteSetting',
		'ReportType',
		'Report',
		'Role',
		'SamlSsoConfig',
		'Scontrol',
		'AccountSettings',
		'ActivitiesSettings',
		'AddressSettings',
		'BusinessHoursSettings',
		'CaseSettings',
		'ChatterAnswersSettings',
		'CompanySettings',
		'ContractSettings',
		'EntitlementSettings',
		'ForecastingSettings',
		'IdeasSettings',
		'KnowledgeSettings',
		'LiveAgentSettings',
		'MobileSettings',
		'OpportunitySettings',
		'OrderSettings',
		'ProductSettings',
		'QuoteSettings',
		'SecuritySettings',
		'CustomSite',
		'StaticResource',
		'SynonymDictionary',
		'CustomTab',
		'Territory',
		'Translations',
		'ApexTrigger',
		'UserCriteriaBasedSharingRule',
		'UserMembershipSharingRule',
		'UserSharingRules',
		'CustomPageWebLink',
		'Workflow'
	};

	private static List<Schema.SObjectType> SERVICE_SOBJECTS = 
	new Schema.SObjectType[] { 
		Metadata_Audit_Run_Log__c.SObjectType,
		Metadata_Audit_Log_Item__c.SObjectType
	};	

	public class OAuth2{
		 public String id{get;set;}
		 public String issued_at{get;set;}
		 public String instance_url{get;set;}
		 public String signature{get;set;}
		 public String access_token{get;set;}    
	}
}