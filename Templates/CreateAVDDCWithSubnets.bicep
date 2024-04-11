@description('Region of the deployment')
param location string = resourceGroup().location

@description('Domain name for Active Directory, ex: tenant.onmicrosoft.com')
param domainName string

@description('Username for the Virtual Machine admin.')
param adminUsername string

@description('Password for the admin.')
@secure()
param adminPassword string

@description('Will add your Public Ip to the NSG rule to allow you to access the VM, ex: can be found there https://ipinfo.io/')
param PublicIP string

@description('Name of the Virtual Machine.')
param vmName string = 'avdlabdc01'

@description('Size of the Virtual Machine.')
param vmSize string = 'Standard_B2ms'

@description('IP addresses of the DNS server.')
param dnsServerIPAddress array = [
  '10.5.1.4'
  '168.63.129.16'
]

@description('Name for the Virtual Network.')
param virtualNetworkName string = 'AVD-Vnet'

@description('Address prefix for the Virtual Network.')
param vnetAddressPrefix string = '10.5.0.0/16'

@description('Name of Identity-Subnet.')
param Identity_Subnet_Name string = 'Identity-Subnet'

@description('Address prefix for Identity-Subnet.')
param Identity_Subnet_Prefix string = '10.5.1.0/24'

@description('Name of SessionHost-Subnet.')
param SessionHost_Subnet_name string = 'SessionHost-Subnet'

@description('Address prefix for SessionHost-Subnet')
param SessionHost_Subnet_Prefix string = '10.5.2.0/24'

@description('Image SKU')
@allowed([
  '2019-Datacenter'
  '2019-datacenter-gensecond'
  '2022-datacenter'
  '2022-datacenter-azure-edition'
  '2022-datacenter-g2'
])
param imageSku string = '2022-datacenter-g2'

var nicName = '${vmName}-nic'
var nsgName = 'AVDLABS-nsg'
var publicIPAddressName = '${vmName}-pubip'
var resourceTags = {
  DeployedWith: 'ARM Template'
  Project: 'AVDLABS'
  CreatedBy: 'SI'
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: nsgName
  location: location
  tags: resourceTags
  properties: {
    securityRules: [
      {
        name: 'AllowRDP'
        properties: {
          access: 'Allow'
          description: 'Allow my public IP to access RDP.'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
          direction: 'Inbound'
          priority: 110
          protocol: '*'
          sourceAddressPrefix: PublicIP
          sourcePortRange: '*'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: virtualNetworkName
  location: location
  tags: resourceTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    dhcpOptions: {
      dnsServers: dnsServerIPAddress
    }
    subnets: [
      {
        name: Identity_Subnet_Name
        properties: {
          addressPrefix: Identity_Subnet_Prefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
      {
        name: SessionHost_Subnet_name
        properties: {
          addressPrefix: SessionHost_Subnet_Prefix
        }
      }
    ]
  }
}

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: publicIPAddressName
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: nicName
  location: location
  tags: resourceTags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, Identity_Subnet_Name)
          }
          publicIPAddress: {
            id: publicIPAddress.id
          }
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource vm 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: vmName
  location: location
  tags: resourceTags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: imageSku
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

resource vmName_CustomScriptExtension 'Microsoft.Compute/virtualMachines/extensions@2020-06-01' = {
  parent: vm
  name: 'CustomScriptExtension'
  location: location
  tags: resourceTags
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {}
    protectedSettings: {
      fileUris: [
        'https://raw.githubusercontent.com/Spiderkilla/Public/main/CreateADDSANDFOREST/Install-AD1.ps1'
      ]
      commandToExecute: 'powershell -ExecutionPolicy Unrestricted -File Install-AD1.ps1 ${domainName} ${adminPassword}'
    }
  }
}
