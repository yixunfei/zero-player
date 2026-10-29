/// Local authorization state is deliberately excluded from user backups.
const installationAccessKey = 'installation-access:v1';
const freshInstallationAccess =
    '{"version":1,"introductionSeen":false,"adultVerified":false,'
    '"protectContentFilter":false,"failures":0,"retryAfter":null}';
const upgradedInstallationAccess =
    '{"version":1,"introductionSeen":true,"adultVerified":true,'
    '"protectContentFilter":false,"failures":0,"retryAfter":null}';
