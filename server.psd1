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
			Include = @('*.pode', '*.ps1', '*.psm1')
			Exclude = @('podex.ps1')
			ShowFiles = $true
		}
		Request = @{
			Timeout = 60
			BodySize = 1MB
		}
	}
	Web = @{
		ErrorPages = @{
			ShowExceptions = $false
			StrictContentTyping = $true
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
		AppName = 'Podex'
		Debug = $false
		DatabaseType = 'SQLite'
		DBFile = './data/podex.db'
		PidFile = 'podex.pid'
	}
}
