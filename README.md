# Websites Fact

This script generates a structured fact.
It extracts and scan documentroot from /etc/apache2/sites-enabled, /etc/httpd/sites-enabled, /etc/nginx/sites-enabled/

Requirement:
* Puppet 4.x or 5.x (or you can patch the shebang for a ruby 2.x)

Known supported CMS
* Joomla: 1.x, 2.x
* Drupal: 6, 7, 8
* Wordpress: 4.x
* PHPBB : 3.x
* Magento
* EZPublish
* Typo3

Example output
```yaml
---
websites:
  my.first.site.com: {}
  my.phpbb.com:
    type: phpbb
    version: 3.2.0
  my.symfony.com:
    type: symfony
    version: 1.4.20
  my.wordpress.com:
    type: wordpress
    version: 4.8.2
    lib:
      ithemes:
        version: 6.6.1
      manual:
        version: '1.12'
      simple:
        version: 3.1.1
      block:
        version: '20170730'
      ft:
        version: 1.2.0
      advanced:
        version: 4.4.12
      head:
        version: 1.4.4
      regenerate:
        version: 2.3.1
      testimonies:
        version: '1.0'
  my.drupal7.com:
    type: drupal
    version: '7.56'
    lib:
      media:
        version: 7.x
      proj4js:
        version: '1.0'
      file:
        version: 7.x
      microdata:
        version: 7.x
      afm:
        version: 7.x
  myjoomla.com:
    type: joomla
    version: 1.5.17
    lib:
      phpmailer:
        version: 2.0.4
```
