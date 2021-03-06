/*

  This is the service class which facilitates extracting metadata information from the org into 
  the Metadata_Audit_Log_Item__c object.

 */

// TODO: Some sort of handling of different API versions?
// TODO: think about whether we want to check whether a metadata type query string is valid

public with sharing class MetadataAuditLogService {

	private static Integer APIVERSION = 37;

	private static String ENTRYTYPE_CREATE = 'Initial create';
	private static String ENTRYTYPE_MOD = 'Modification';
	private static String ENTRYTYPE_DELETE = 'Deletion';

	private static String CUSTOMSETTING_NAME = 'Automated';

	private static Integer MAXLOGSIZE = 131072;

	private static String logString = '';

	private static String fetchErrorMessage = null;

	public MetadataAuditLogService() {

	}

	public static void fetchAllMetadataFromOrg() {

	}

	public static void fetchAndProcessType(String metadataType, Id currentJobId) {
		Long startTime = System.currentTimeMillis();
		fetchErrorMessage = null;
		MetadataService.FileProperties[] fp = fetchMetadataTypeFromOrg(metadataType, currentJobId);
		processMetadata(fp, metadataType, currentJobId);
		Long finishTime = System.currentTimeMillis();
		String itemsReturnedText = generateItemsReturnedText(fp);

		logLine('Metadata: ' + metadataType + ', time taken (ms): ' + (finishTime - startTime)+ ', ' + itemsReturnedText);

		// now fetch and update the job log object

		MetadataAuditJobLogSelector jobLogSelector = new MetadataAuditJobLogSelector();
		List<Metadata_Audit_Job_Log__c> jobLogs = jobLogSelector.selectById(new Set<Id> { currentJobId});

		if (jobLogs != null && jobLogs.size() == 1) {
			Metadata_Audit_Job_Log__c myJobLog = jobLogs[0];
			
			// check if total logstring would exceed max field size

			if (logString.length() + myJobLog.Execution_Log__c.length() > MAXLOGSIZE) {
				//truncate here - retaining the last 255 characters

				Integer currentLogSize = myJobLog.Execution_Log__c.length();

				myJobLog.Execution_Log__c = (myJobLog.Execution_Log__c + logString).abbreviate(MAXLOGSIZE - 255) 
					+ logString.substring(logString.length() - 255);

			} else {
				//System.debug('myJobLog.Execution_Log__c before: ' + myJobLog.Execution_Log__c);
				//System.debug('logString received: ' + logString);
				myJobLog.Execution_Log__c += '\n' + logString;
				//System.debug('myJobLog.Execution_Log__c after: ' + myJobLog.Execution_Log__c);
			}

			update myJobLog;

		} else {
			// some weirdness occurred - just log to debug

			System.debug(LoggingLevel.ERROR, 'Error logging to job log. Log follows.');			
			System.debug(LoggingLevel.ERROR, logString);
		}


	}

	public static MetadataService.FileProperties[] fetchMetadataTypesFromOrg(String[] metadataTypeNames, Id currentJobId) {
		System.debug(LoggingLevel.DEBUG, 'Job Log Id: ' + currentJobId);
		System.debug(LoggingLevel.DEBUG, 'MD Types: ' + metadataTypeNames);
		
		MetadataService.MetadataPort service = new MetadataService.MetadataPort();


		// do the callout to get a sessionid using named credentials

		MetadataAuditSettings__c mySettings = MetadataAuditSettings__c.getInstance(CUSTOMSETTING_NAME);
		System.debug(LoggingLevel.FINE, 'Custom setting with params: ' + mySettings);

		// TODO: test if we did get the custom setting back, if not something is seriously wrong

		HttpRequest request = new HttpRequest();

		request.setEndpoint(mySettings.Endpoint__c); // sfdc sandbox
		request.setMethod('POST');
		request.setTimeout(60000);

		request.setBody(
		                'grant_type=password' +
		                '&client_id=' + EncodingUtil.urlEncode(mySettings.Consumer_Key__c, 'UTF-8') +
		                '&client_secret=' + EncodingUtil.urlEncode(mySettings.Consumer_Secret__c, 'UTF-8') +
		                '&username=' + EncodingUtil.urlEncode(mySettings.Username__c, 'UTF-8') +
		                '&password=' + EncodingUtil.urlEncode(mySettings.Password__c, 'UTF-8')
		);
		System.debug(LoggingLevel.FINE, 'Request body: ' + request.getBody());

		HttpResponse response = new Http().send(request);
		System.debug('Response body: ' + response.getBody() + ' Status: ' + response.getStatus());


		try {
			OAuth2 oauth2 = (OAuth2) JSON.deserialize(
			                                          response.getBody(),
			                                          MetadataAuditLogService.OAuth2.class
			);
			service.SessionHeader = new MetadataService.SessionHeader_element();
			service.SessionHeader.sessionId = oauth2.access_token;
		} catch(Exception whoops) {
			System.debug('OAuthException: ' + whoops.getTypeName() + ': ' + whoops.getMessage());
		}

		// TODO: test if we have a valid session - if not, no point in trying to connect just to get errors

		System.debug(LoggingLevel.DEBUG, 'Session id: ' + service.SessionHeader.sessionId);

		if (service.SessionHeader.sessionId != null) {

			List<MetadataService.ListMetadataQuery> queries = new List<MetadataService.ListMetadataQuery> ();
			for (String metadataTypeName : metadataTypeNames) {
				MetadataService.ListMetadataQuery query = new MetadataService.ListMetadataQuery();
				query.type_x = metadataTypeName;
				queries.add(query);
			}
			try {
				MetadataService.FileProperties[] retval = service.listMetadata(queries, APIVERSION);
				return retval;
			} catch (Exception e) {
				System.debug(LoggingLevel.DEBUG, 'Callout caused exception: ');
				System.debug(LoggingLevel.DEBUG, e.getCause());
				System.debug(LoggingLevel.DEBUG, e.getMessage());
				System.debug(LoggingLevel.DEBUG, e.getLineNumber());
				fetchErrorMessage = e.getMessage();
			}
		} else {
			System.debug(LoggingLevel.DEBUG, 'Invalid session detected, skipping operation.');
		}
		return null;
		
	}

	public static MetadataService.FileProperties[] fetchMetadataTypeFromOrg(String metadataTypeName, Id currentJobId) {
		return fetchMetadataTypesFromOrg(new String[] { metadataTypeName }, currentJobId);
	}


	public static void processMetadata(MetadataService.FileProperties[] fpList, String mdType, Id currentJobId) {

		System.debug(LoggingLevel.DEBUG, 'Job Log Id: ' + currentJobId);

		fflib_SObjectUnitOfWork uow = new fflib_SObjectUnitOfWork(SERVICE_SOBJECTS);

		// check whether we got anything back in the fpList - if not, log and move on

		Metadata_Audit_Run_Log__c runLog = new Metadata_Audit_Run_Log__c();
		runLog.Metadata_category__c = mdType;
		runLog.Items_added__c = 0;
		runLog.Items_deleted__c = 0;
		runLog.Items_modified__c = 0;
		runLog.Metadata_Audit_Job_Log__c = currentJobId;
		
		runLog.Number_of_query_items_returned__c = (fpList != null) ? fpList.size() : 0;
		runlog.Error_returned__c = true;

		uow.registerNew(runLog);

		if (fpList != null && fpList.size() > 0) {	

			if (fpList.size() != 0) {
				// get a map by Metadata_Item_ID__c field rather than list
				// will also get rid of duplicate items for us

				MetadataAuditLogItemsSelector maliSelector = new MetadataAuditLogItemsSelector();

				List<Metadata_Audit_Log_Item__c> existingItems = maliSelector.selectExistingByTypeOldestFirst(mdType);
				Map<String, Metadata_Audit_Log_Item__c> existingItemsMap = new Map<String, Metadata_Audit_Log_Item__c> ();
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

				Map<String, Metadata_Audit_Log_Item__c> incomingMalis = new Map<String, Metadata_Audit_Log_Item__c> ();

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
			
		} else {
			System.debug(LoggingLevel.DEBUG, 'Null or zero-length list of FileProperties received for metadata: ' + mdType + ', skipping...');
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
		Metadata_Audit_Log_Item__c.SObjectType, 
		Metadata_Audit_Job_Log__c.SObjectType
	};

	public class OAuth2 {
		public String id { get; set; }
		public String issued_at { get; set; }
		public String instance_url { get; set; }
		public String signature { get; set; }
		public String access_token { get; set; }
	}

	private static void logLine (String line) {
		logString += line + '\n';
	}

	private static String generateItemsReturnedText(MetadataService.FileProperties[] fp) {
		String itemsReturnedText = '';
		if (fetchErrorMessage != null) {
			// we had a fetch error
			itemsReturnedText = 'nothing fetched - error: ' + fetchErrorMessage;
		} else {
			itemsReturnedText = 'items returned: ' + (fp == null ? '0' : String.valueOf(fp.size()));
		}
		itemsReturnedText += '\n \n';
		return itemsReturnedText;
		
	}
}