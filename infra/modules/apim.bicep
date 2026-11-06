// ============================================================================
// API Management Module - Enterprise API Gateway
// ============================================================================

@description('API Management name')
param apimName string

@description('Location')
param location string

@description('Tags')
param tags object

@description('Function App name')
param functionAppName string

@description('Publisher email')
param publisherEmail string = 'admin@contoso.com'

@description('Publisher name')
param publisherName string = 'Enterprise Doc Platform'

// APIM Consumption tier - deploy in eastus for availability
resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimName
  location: 'eastus'
  tags: tags
  sku: {
    name: 'Consumption'
    capacity: 0
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// Document Processing API
resource documentApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apim
  name: 'document-api'
  properties: {
    displayName: 'Document Processing API'
    description: 'API for document upload, processing, and retrieval'
    subscriptionRequired: true
    path: 'documents'
    protocols: ['https']
  }
}

// Upload Document Operation
resource uploadOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: documentApi
  name: 'upload-document'
  properties: {
    displayName: 'Upload Document'
    method: 'POST'
    urlTemplate: '/upload'
    responses: [
      { statusCode: 202, description: 'Accepted' }
    ]
  }
}

// Get Status Operation
resource statusOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: documentApi
  name: 'get-status'
  properties: {
    displayName: 'Get Processing Status'
    method: 'GET'
    urlTemplate: '/{documentId}/status'
    templateParameters: [
      { name: 'documentId', type: 'string', required: true }
    ]
    responses: [
      { statusCode: 200, description: 'OK' }
    ]
  }
}

// Search Documents Operation
resource searchOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: documentApi
  name: 'search-documents'
  properties: {
    displayName: 'Search Documents'
    method: 'POST'
    urlTemplate: '/search'
    responses: [
      { statusCode: 200, description: 'OK' }
    ]
  }
}

// Rate Limiting Policy
resource globalPolicy 'Microsoft.ApiManagement/service/policies@2023-05-01-preview' = {
  parent: apim
  name: 'policy'
  properties: {
    value: '<policies><inbound><base /><rate-limit calls="100" renewal-period="60" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
    format: 'xml'
  }
}

// Product for external developers
resource product 'Microsoft.ApiManagement/service/products@2023-05-01-preview' = {
  parent: apim
  name: 'document-platform'
  properties: {
    displayName: 'Document Platform'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

resource productApi 'Microsoft.ApiManagement/service/products/apis@2023-05-01-preview' = {
  parent: product
  name: documentApi.name
}

output apimName string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output developerPortalUrl string = apim.properties.developerPortalUrl
