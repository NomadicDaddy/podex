@{
	Server = @{
		AutoImport = @{
			Modules = @{
				Enable = $true
				ExportOnly = $true
			}
			Snapins = @{
				Enable = $false
			}
		}
        FileMonitor = @{
            Enable = $false
			Include = @("*.pode", "*.ps1")
			Exclude = @('podex.ps1')
            ShowFiles = $true
        }
		Request = @{
				Timeout = 600
		}
	}
	Web = @{
		ErrorPages = @{
			ShowExceptions = $true
		}
		Static = @{
			Cache = @{
				Enable = $false
			}
		}
	}
	PodeCfg = @{
		HttpPort = 8433
		HttpUrl = 'localhost'
		CertThumbprint = ''
		HttpsEnabled = $false
	}
	Podex = @{
		Debug = $false
		DatabaseType = 'SQLite'
		DBFile = './data/podex.db'
	}
}
