# winonarma
Powershell kullanarak windows derin bakım ve onarım

.ÖZET
Gelişmiş Bakım, Optimizasyon ve Onarım Aracı V-01
Seçkin Akay tarafından düzenlendi ve güncellendi | Güncelleme: 2026-09-26
Kaynaklar - Açık kaynak geliştiricisi Steve projelerinden ve Gemini ai sohbet ajanlarından yararlanıldı.
.AÇIKLAMA
MSP saha ve uzaktan kullanımına yönelik, otomatik Windows 10/11 disk alanı geri kazanımı ve bütünlük onarımı aracı. 
Dell SupportAssist anlık görüntülerini (snapshots), tarayıcı, Office ve GPU önbelleklerini, Geri Dönüşüm Kutusu'nu, 
Teslimat İyileştirme (Delivery Optimization) verilerini, yükleyici önbelleğini, arama dizinini ve eski Windows.old klasörünü temizler; 
Windows Update veritabanını sıfırlar; DISM ve SFC onarımlarını gerçekleştirir; hazırda bekletme dosyasını kaldırır; 
ayrıca SSD TRIM işlemini uygularken her aşamada geri kazanılan disk alanı miktarını raporlar.

V-01 kapsam değişikliği: gizlilik/telemetri sıkılaştırma (eski Bölge 1), tarayıcı sıkılaştırma/uBlock
(eski Bölge 2) ve OEM/yazılım gereksiz bileşen temizliği (eski Bölge 3) kapsamdan çıkarıldı. 
Yalnızca temizlik ve onarım işlemlerini kapsar; canlı ve yönetilen uç noktalarda çalıştırılması güvenlidir.
.PARAMETER DryRun
Salt okunur tahmin modu. Herhangi bir değişiklik yapmaz; yıkıcı nitelikteki tüm adımlar atlanır
ve bunun yerine her bir hedef için boyutlandırma yapılarak, kategori bazında geri kazanılacak
tahmini alan miktarı ile öngörülen toplam boş alan bilgisi raporlanır. Disk uyarısı üzerine işlem yapmadan önce kullanın.
OFLINE ÇALIŞTIRMAK İÇİN
akay.txt dosyasını .bat uzantısı ile kaydedin ve akay01.ps1 dosyası ile aynı dizinde yada sürücüde olaması yeterlidir çalışacaktır.
