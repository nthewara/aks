@description('AKS cluster name')
param name string
param location string

@description('Subnet ID for the system node pool')
param aksSubnetId string

@description('Log Analytics workspace ID for OMS agent')
param logAnalyticsWorkspaceId string

@description('Entra group object IDs that get cluster-admin via AAD profile (ops-admins)')
param adminGroupObjectIDs array

@description('Kubernetes version, e.g. 1.30.6')
param kubernetesVersion string = '1.30'

@description('Node count for system pool')
param nodeCount int = 2

@description('Node VM SKU')
param nodeVmSize string = 'Standard_D2s_v5'

@description('Pod CIDR for overlay (must NOT overlap VNet)')
param podCidr string = '10.244.0.0/16'

@description('Service CIDR (must NOT overlap VNet or podCidr)')
param serviceCidr string = '10.245.0.0/16'

@description('DNS service IP inside serviceCidr')
param dnsServiceIp string = '10.245.0.10'

resource aks 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: name
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: name
    enableRBAC: true
    disableLocalAccounts: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
      adminGroupObjectIDs: adminGroupObjectIDs
      tenantID: subscription().tenantId
    }
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      networkPolicy: 'cilium'
      podCidr: podCidr
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIp
      loadBalancerSku: 'standard'
    }
    agentPoolProfiles: [
      {
        name: 'sys'
        mode: 'System'
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        vnetSubnetID: aksSubnetId
        type: 'VirtualMachineScaleSets'
      }
    ]
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
    }
  }
}

output id string = aks.id
output name string = aks.name
output kubeletIdentityObjectId string = aks.properties.identityProfile.kubeletidentity.objectId
