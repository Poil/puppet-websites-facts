#!/opt/puppetlabs/puppet/bin/ruby
ENV['FACTERLIB']='/opt/puppetlabs/puppet/cache/lib/facter'
require 'facter'
require 'yaml'
require 'pathname'

if File.exists?('/etc/websites.yml')
    extra_path = YAML.load_file('/etc/websites.yml')
end

websites = { 'websites' => {} }
if Facter.value(:kernel) == "Linux"
    osfamily = Facter.value(:osfamily)
    apache_conf_path = case osfamily
                       when "RedHat" then "/etc/httpd/sites-enabled"
                       when "Debian" then "/etc/apache2/sites-enabled"
                       end
    nginx_conf_path='/etc/nginx/sites-enabled/'


    vhosts_hash = {}
    if File.directory?(apache_conf_path)
        Dir.foreach(apache_conf_path) do |item|
            next if item == '.' or item == '..' or File.directory?(File.join(apache_conf_path, item))
            pn = Pathname.new(File.join(apache_conf_path, item))
            next if !File.exist?(pn.realpath())
            File.open(File.join(apache_conf_path, item)) do |conf|
                text = conf.read
                server_name = nil
                document_root = nil

                text.each_line do |line|
                    # Apache
                    if line =~ /^\s*(ServerName)\s.*/
                        server_name = line.gsub(/"|'/, '').sub('ServerName ', '').lstrip.strip
                    elsif line =~ /^\s*(DocumentRoot)\s.*/
                        document_root = line.gsub(/"|'/, '').sub('DocumentRoot ', '').lstrip.strip
                    elsif line =~ /^\s*<\/VirtualHost>/
                        vhosts_hash[server_name] = document_root if server_name && document_root
                        server_name = nil
                        document_root = nil
                    end
                end
            end
        end
    end
    if File.directory?(nginx_conf_path)
        Dir.foreach(nginx_conf_path) do |item|
            next if item == '.' or item == '..' or File.directory?(File.join(nginx_conf_path, item))
            pn = Pathname.new(File.join(nginx_conf_path, item))
            next if !File.exist?(pn.realpath())
            File.open(File.join(nginx_conf_path, item)) do |conf|
                text = conf.read
                server_name = nil
                document_root = nil

                text.each_line do |line|
                    ## Nginx
                    if line =~ /^\s*(server_name)\s.*;/
                        server_name = line.gsub(/"|'/, '').sub('server_name ', '').lstrip.strip.sub(';', '').split(' ')[0]
                    elsif line =~ /^\s*(root)\s.*;/
                        document_root = line.gsub(/"|'/, '').sub('root ', '').lstrip.strip.sub(';', '')
                    elsif line =~ /^server \{/
                        # If there is more than one block in the current config file
                        vhosts_hash[server_name] = document_root if server_name && document_root
                        server_name = nil
                        document_root = nil
                    end
                end
                # At the end of the last block get
                vhosts_hash[server_name] = document_root if server_name && document_root
                server_name = nil
                document_root = nil
            end
        end
    end

    # merge extra_path to autodetected vhosts
    if extra_path
        extra_path.each do |ep|
          vhosts_hash[ep['domain']] = ep['root']
        end
    end

    # parse websites
    vhosts_hash.each do |domain, root|
        next if domain == 'default'

        if domain and root
            if !websites['websites'][domain]
                websites['websites'][domain] = {}
            end
            if File.directory?(root)
                # DRUPAL
                drupal_find = [ File.join(root, 'includes', 'bootstrap.inc'),
                                File.join(root, 'modules', 'system', 'system.module')
                ]
                drupal_find.each do |drupal|
                    if File.exists?(drupal)
                        File.open(drupal) do |site_info|
                            site_file = site_info.read
                            n = /define\('VERSION',\s*'([\.\d]+)'\);/.match(site_file)
                            if n
                                websites['websites'][domain]['type'] = 'drupal'
                                websites['websites'][domain]['version'] = n[1]
                                websites['websites'][domain]['lib'] = {}
                            end
                        end
                        drupal_plugins = File.join(root, 'sites')
                        if Dir.exists?(drupal_plugins)
                            Dir.glob("#{drupal_plugins}/*/modules/*/*/*.info") do |plugin|
                                n = nil
                                v = nil
                                File.open(plugin) do |plugin_info|
                                    plugin_file = plugin_info.read
                                    n = /name\s*=\s*([\w]+([\s]+[\w]+)?)$/.match(plugin_file)
                                    vt = /version\s*=\s*"?([\w\-.]+)"?$/.match(plugin_file)
                                    v = vt if vt and not vt[1].include?('VERSION')
                                end
                                if n
                                    v = ['', 'unknown'] if not v
                                    websites['websites'][domain]['lib'][n[1].tr('"', '').downcase] = { 'version' => v[1] }
                                end
                            end
                        end
                    end
                end
                # DRUPAL_8
                drupal_find = [ File.join(root,'core/lib','Drupal.php'),
                                #File.join(root,'modules','system','system.module')
                ]
                drupal_find.each do |drupal|
                    if File.exists?(drupal)
                        File.open(drupal) do |site_info|
                            site_file = site_info.read
                            n = /\s\sconst\sVERSION\s=\s'([\.\d]+)';/.match(site_file)
                            if n
                                websites['websites'][domain]['type'] = 'drupal'
                                websites['websites'][domain]['version'] = n[1]
                                websites['websites'][domain]['lib'] = {}
                            end
                        end
                        drupal_plugins = File.join(root, 'modules')
                        if Dir.exists?(drupal_plugins)
                            Dir.glob("#{drupal_plugins}/*/*/*.info.yml") do |plugin|
                                n = nil
                                v = nil
                                File.open(plugin) do |plugin_info|
                                    plugin_file = plugin_info.read
                                    n = /name\s*:\s*'?([\w]+([\s]+[\w]+)?)'?$/.match(plugin_file)
                                    vt = /version\s*:\s*'?([\w\-.]+)'?$/.match(plugin_file)
                                    v = vt if vt and not vt[1].include?('VERSION')
                                end
                                if n
                                    v = ['', 'unknown'] if not v
                                    websites['websites'][domain]['lib'][n[1].downcase] = { 'version' => v[1] }
                                end
                            end
                        end
                    end
                end
                # Wordpress
                wordpress = File.join(root,'wp-includes','version.php')
                if File.exists?(wordpress)
                    File.open(wordpress) do |site_info|
                        site_file = site_info.read
                        n = /\$wp_version\s*=\s*'([\d.]+)'/.match(site_file)
                        if n
                            websites['websites'][domain]['type'] = 'wordpress'
                            websites['websites'][domain]['version'] = n[1]
                            websites['websites'][domain]['lib'] = {}
                        end
                    end
                    wordpress_plugins = File.join(root,'wp-content', 'plugins')
                    if Dir.exists?(wordpress_plugins)
                        Dir.glob("#{wordpress_plugins}/*/*.php") do |plugin|
                            n = nil
                            v = nil
                            File.open(plugin) do |plugin_info|
                                plugin_file = plugin_info.read
                                n = /Plugin Name\s*:\s*([\w]+)/.match(plugin_file)
                                v = /Version\s*:\s*([\d.]+)/.match(plugin_file)
                            end
                            if n && v
                                websites['websites'][domain]['lib'][n[1].downcase] = { 'version' => v[1] }
                            end
                        end
                    end
                end
                wordpress_smtp = File.join(root,'wp-includes','class-phpmailer.php')
                if File.exists?(wordpress_smtp)
                    File.open(wordpress_smtp) do |wordpress_phpmailer|
                        smtp_file = wordpress_phpmailer.read
                        n = /^\|\s*Version:\s*([\.\d]+)\s*\|/.match(smtp_file)
                        if n
                            websites['websites'][domain]['lib']['phpmailer'] = { 'version' => n[1] }
                        end
                    end
                end
                # PHPBB
                phpbb = File.join(root,'includes','constants.php')
                if File.exists?(phpbb)
                    File.open(phpbb) do |site_info|
                        site_file = site_info.read
                        n = /define\('PHPBB_VERSION',\s*'([\.\d]+)'\);/.match(site_file)
                        if n
                            websites['websites'][domain]['type'] = 'phpbb'
                            websites['websites'][domain]['version'] = n[1]
                        end
                    end
                end
                # Typo3 - 4
                typo3 = File.join(root,'t3lib','config_default.php')
                if File.exists?(typo3)
                    File.open(typo3) do |site_info|
                        site_file = site_info.read
                        n = /\$TYPO_VERSION\s*=\s*'([\d.]+)'/.match(site_file)
                        if n
                            websites['websites'][domain]['type'] = 'typo3'
                            websites['websites'][domain]['version'] = n[1]
                        end
                    end
                end
                # Typo3 - 7
                typo3 = File.join(root,'typo3_src', 'typo3', 'sysext', 'core', 'ext_emconf.php')
                if File.exists?(typo3)
                    File.open(typo3) do |site_info|
                        site_file = site_info.read
                        n = /'version'\s*=>\s*'?([\d\w\-\.]+)'?,?$/.match(site_file)
                        if n
                            websites['websites'][domain]['type'] = 'typo3'
                            websites['websites'][domain]['version'] = n[1]
                            websites['websites'][domain]['lib'] = {}
                        end
                    end
                    typo3_plugins = File.join(root, 'typo3conf', 'ext')
                    if Dir.exists?(typo3_plugins)
                        Dir.glob("#{typo3_plugins}/*/ext_emconf.php") do |plugin|
                            n = nil
                            v = nil
                            File.open(plugin) do |plugin_info|
                                plugin_file = plugin_info.read.gsub /\r\n?/, "\n"
                                n = /'title'\s*=>\s*'?([\w|\d|\s|\-]+)'?,?$/.match(plugin_file)
                                v = /'version'\s*=>\s*'?([\d|\w|\-|\.]+)'?,?$/.match(plugin_file)
                            end
                            if n and v
                                websites['websites'][domain]['lib'][n[1].downcase] = { 'version' => v[1] }
                            end
                        end
                    end
                end
                # Joomla
                joomla_find = [File.join(root,'libraries','cms','version','version.php'),
                               File.join(root,'includes','version.php'), 
                               File.join(root,'libraries','joomla','version.php')]
                joomla_find.each do |joomla|
                    if File.exists?(joomla)
                        File.open(joomla) do |site_info|
                            site_file = site_info.read.gsub /\r\n?/, "\n"
                            n = /\w+ \$RELEASE\s*=\s*'([\d.]+)'/.match(site_file)
                            o = /\w+ \$DEV_LEVEL\s*=\s*'([\d.]+)'/.match(site_file)
                            if n and o
                                websites['websites'][domain]['type'] = 'joomla'
                                websites['websites'][domain]['version'] = n[1]+'.'+o[1]
                            end
                        end
                        joomla_cve = File.join(root,'libraries','joomla','session','session.php')
                        if File.exists?(joomla_cve)
                            File.open(joomla_cve) do |joomla_session|
                                cve = joomla_session.find { |line| line =~ Regexp.new(Regexp.quote("if (isset($_SERVER['HTTP_X_FORWARDED_FOR']))")) }
                                if cve
                                    websites['websites'][domain]['cve'] = ['cve_2015-8562']
                                end
                                joomla_session.rewind
                                cve = joomla_session.find { |line| line =~ Regexp.new(Regexp.quote("protected $data;")) }
                                if cve
                                    websites['websites'][domain]['cve'] = ['cve_2015-8562b']
                                end
                            end
                        end
                        joomla_smtp = File.join(root,'libraries','phpmailer','smtp.php')
                        if File.exists?(joomla_smtp)
                            File.open(joomla_smtp) do |joomla_phpmailer|
                                smtp_file = joomla_phpmailer.read.gsub /\r\n?/, "\n"
                                n = /^\|\s*Version:\s*([\.\d]+)\s*\|/.match(smtp_file)
                                if n
                                    websites['websites'][domain]['lib'] = { 'phpmailer' => { 'version' => n[1] } }
                                end
                            end
                        end
                    end
                end
                # Symfony
                symfony = File.join(root, '..', 'lib', 'vendor', 'symfony', 'lib', 'autoload', 'sfCoreAutoload.class.php')
                if File.exists?(symfony)
                    File.open(symfony) do |site_info|
                        site_file = site_info.read.gsub /\r\n?/, "\n"
                        n = /define\('SYMFONY_VERSION',\s*'([\.\d]+)'\);/.match(site_file)
                        if n
                            websites['websites'][domain]['type'] = 'symfony'
                            websites['websites'][domain]['version'] = n[1]
                        end
                        symfony_swift = File.join(root, '..', 'lib', 'vendor', 'swiftmailer', 'swiftmailer', 'VERSION')
                        if File.exists?(symfony_swift)
                            File.open(symfony_swift) do |symfony_swiftmailer|
                                smtp_file = symfony_swiftmailer.read.gsub /\r\n?/, "\n"
                                n = /Swift-([\d.]+)/.match(smtp_file)
                                if n
                                    websites['websites'][domain]['lib'] = { 'swiftmailer' => { 'version' => n[1] } }
                                end
                            end
                        end
                    end
                end
                # Symfony2
                symfony = File.join(root,'..', 'vendor', 'symfony', 'symfony', 'src', 'Symfony', 'Component', 'HttpKernel', 'Kernel.php')
                if File.exists?(symfony)
                    File.open(symfony) do |site_info|
                        site_file = site_info.read.gsub /\r\n?/, "\n"
                        n = /\s+const\s+VERSION\s+=\s+'([\d.]+)'/.match(site_file)
                        if n
                            websites['websites'][domain]['type'] = 'symfony'
                            websites['websites'][domain]['version'] = n[1]
                        end
                        symfony_swift = File.join(root,'..','vendor','swiftmailer','swiftmailer','VERSION')
                        if File.exists?(symfony_swift)
                            File.open(symfony_swift) do |symfony_swiftmailer|
                                smtp_file = symfony_swiftmailer.read.gsub /\r\n?/, "\n"
                                n = /Swift-([\d.]+)/.match(smtp_file)
                                if n
                                    websites['websites'][domain]['lib'] = { 'swiftmailer' => { 'version' => n[1] } }
                                end
                            end
                        end
                    end
                end
                # Ez Publish
                ezpublish_find = [File.join(root,'lib','version.php'),
                                  File.join(root,'ezpublish_legacy','lib','version.php')]
                ezpublish_find.each do |ezpublish|                  
                    if File.exists?(ezpublish)
                        File.open(ezpublish) do |site_info|
                            site_file = site_info.read.gsub /\r\n?/, "\n"
                            n = site_file.scan(/\s+const\s+VERSION_(?:MAJOR|MINOR|RELEASE)\s+=\s+(\d+);/)
                            if n[0]
                                websites['websites'][domain]['type'] = 'ezpublish'
                                websites['websites'][domain]['version'] = n.join('.')
                            end
                        end
                    end
                end
                # Magento
                magento_find = [File.join(root,'app','Mage.php'),
                                File.join(root,'server','app','Mage.php')]
                magento_find.each do |magento| 
                    if File.exists?(magento)
                        File.open(magento) do |site_info|
                            site_file = site_info.read.gsub /\r\n?/, "\n"
                            n = /\s+'(?:major|minor|revision|patch)'\s+=>\s+'(\d+)'/.match(site_file)
                            if n
                                websites['websites'][domain]['type'] = 'magento'
                                websites['websites'][domain]['version'] = n.join('.')
                            end
                        end
                    end
                end
                # PHPMyAdmin
                phpmyadmin_find = [File.join(root,'libraries','Config.class.php')]
                phpmyadmin_find.each do |phpmyadmin|                  
                    if File.exists?(phpmyadmin)
                        File.open(phpmyadmin) do |site_info|
                            site_file = site_info.read.gsub /\r\n?/, "\n"
                            n = /\s*\(.*PMA_VERSION.*,\s*'([\d\.]+)'\);/.match(site_file)
                            if n
                                websites['websites'][domain]['type'] = 'phpmyadmin'
                                websites['websites'][domain]['version'] = n[1]
                            end
                        end
                    end
                end
                # SPIP
                spip_find = [File.join(root,'ecrire','inc_version.php')]
                spip_find.each do |spip|                  
                    if File.exists?(spip)
                        File.open(spip) do |site_info|
                            site_file = site_info.read.gsub /\r\n?/, "\n"
                            n = /\$spip_version_branche\s*=\s*"?([\d\.]+)"?;$/.match(site_file)
                            if n
                                websites['websites'][domain]['type'] = 'spip'
                                websites['websites'][domain]['version'] = n[1]
                            end
                        end
                    end
                end
                # Mantis
                mantis_find = [File.join(root,'core','constant_inc.php')]
                mantis_find.each do |mantis|                  
                    if File.exists?(mantis)
                        File.open(mantis) do |site_info|
                            site_file = site_info.read.gsub /\r\n?/, "\n"
                            n = /define\(\s*'MANTIS_VERSION'\s*,\s*'([\.\d]+)'\s*\);/.match(site_file)
                            if n
                                websites['websites'][domain]['type'] = 'mantis'
                                websites['websites'][domain]['version'] = n[1]
                            end
                        end
                    end
                end
            end
        end
    end
end

if !websites['websites'].empty?
    File.write('/etc/facter/facts.d/websites.yaml', websites.to_yaml)
end

