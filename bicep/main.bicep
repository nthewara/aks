targetScope = 'resourceGroup'

@description('Prefix for resource names')
param prefix string = 'akslab'

@description('Location')
param location string = resourceGroup().location

@description('Entra group object IDs for cluster admin (ops-admins). Empty array OK for Phase 1.')
param opsAdminGroupObjectIds array = []

var uniq = take(uniqueString(resourceGroup().id), 5)
var p = '${prefix}-${uniq}'

module vnet 'modules/vnet.bicep' = {
  name: 'vnet'
  params: {
    name: '${p}-vnet'
    location: location
  }
}

module law 'modules/log-analytics.bicep' = {
  name: 'law'
  params: {
    name: '${p}-law'
    location: location
  }
}

module aks 'modules/aks.bicep' = {
  name: 'aks'
  params: {
    name: '${p}-aks'
    location: location
    aksSubnetId: vnet.outputs.aksSubnetId
    logAnalyticsWorkspaceId: law.outputs.id
    adminGroupObjectIDs: opsAdminGroupObjectIds
  }
}

output aksName string = aks.outputs.name
output aksId string = aks.outputs.id
output vnetId string = vnet.outputs.id
