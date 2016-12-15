# MetadataAudit

Security setup:

1. Create Remote Site Setting for own URL
2. Create Auth Provider: give it a name and leave everything else blank.
3. Create Connected App with api and refresh_token OAuth permissions. Fake a callback URL subsituting correct values from your Auth provider: 	https://test.salesforce.com/services/authcallback/00DO0000004u9rLMAQ/MyAuthprovider
4. Go back to Auth Provider, and update scope with api refresh_token as well as the consumer key/secret generated in the connected app
5. Give the relevant users access to the newly created connected ap through profile/permissionset
