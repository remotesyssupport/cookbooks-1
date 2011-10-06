require 'base64'

ruby_block "set osd id" do
  block do
    node.set[:ceph][:osd_id] = search(:node, 'recipes:ceph\:\:osd').size
  end
  not_if { node[:ceph][:osd_id] } 
end

include_recipe "ceph"
directory "/tmp/ceph-stage2"

%w(/tmp/ceph-stage2/conf /etc/ceph/ceph.conf).each do |conf|
  template conf do
    source "ceph.conf.erb"
    variables(
      :mon => search(:node, 'recipes:ceph\:\:mon'),
      :mds => search(:node, 'recipes:ceph\:\:mds'),
      :osd => search(:node, 'recipes:ceph\:\:osd')
    )
  end
end

template "/tmp/ceph-stage2/caps" do
  source "caps.erb"
end

# mozna zamienic na
# node["recipies"].include?("ceph:osd")
# osd_id juz wskazuje ze jest osd, zamienic kolejnoscia warunki - drugi jest prostszy - szybszy
if node[:ceph][:osd_id] && search(:node, 'recipes:ceph\:\:osd').size == 1
  # zapisuje sie monmap z wezla mon w folderze /tmp/ceph-stage2/monmap
  if search(:node, 'recipes:ceph\:\:mon').first[:ceph][:monmap]
    file "/tmp/ceph-stage2/monmap" do
      content Base64.decode64(search(:node, 'recipes:ceph\:\:mon').first[:ceph][:monmap])
    end
  end

  # za pomoca mkcephfs inicjalizujemy wezel osd, tworzone sa pliki key.osd.$id oraz keyring.osd.$id
  execute "init osd" do
    command "mkcephfs -c /etc/ceph/ceph.conf -d /tmp/ceph-stage2 --init-local-daemons osd"
    #not_if { File.exists?("/tmp/ceph-stage2/key.osd.*") }
    only_if { File.exists?("/tmp/ceph-stage2/monmap") && (not File.exists?("/tmp/ceph-stage2/key.osd.#{node[:ceph][:osd_id]}")) }
    notifies :create, "ruby_block[read key && keyring]"
  end

  # pliki utworzone podczas inicjalizacji sa zapisywane w wezle
  ruby_block "read key && keyring" do
    action :nothing
    block do
      key = Base64.encode64(File.read("/tmp/ceph-stage2/key.osd.#{node[:ceph][:osd_id]}"))
      node.set[:ceph][:osd][:key] = key
      keyring = Base64.encode64(File.read("/tmp/ceph-stage2/keyring.osd.#{node[:ceph][:osd_id]}"))
      node.set[:ceph][:osd][:keyring] = keyring
    end
    not_if { node[:ceph][:osd] }
  end
elsif node[:ceph][:osd_id] && node[:ceph][:osd_id] != 0 && search(:node, 'recipe:ceph\:\:osd').size > 1 && File.read("/etc/ceph/ceph.conf").include?("[osd.#{node[:ceph][:osd_id]}]")
  # add osd to cluster

  execute "get monmap" do
    command "ceph mon getmap -o /tmp/ceph-stage2/monmap"
  end

  execute "initialize osd fs" do
    command "cosd -c /etc/ceph/ceph.conf -i #{node[:ceph][:osd_id]} --mkfs --monmap /tmp/ceph-stage2/monmap"
  end

  execute "create key && keyring" do
    command "cauthtool --create-keyring /tmp/ceph-stage2/keyring.mds.#{node[:ceph][:osd_id]} && cauthtool --gen-key --caps=/tmp/ceph-stage2/caps --name=osd.#{node[:ceph][:osd_id]} /tmp/ceph-stage2/keyring.osd.#{node[:ceph][:osd_id]}"
  end
  
  execute "add osd to authorized machines" do
    command "ceph auth add osd.#{node[:ceph][:osd_id]} osd 'allow *' mon 'allow rwx' -i /tmp/ceph-stage2/keyring.osd.#{node[:ceph][:osd_id]}"
  end
  
  execute "set osd count" do
    command "ceph osd setmaxosd #{search(:node, 'recipe:ceph\:\:osd').size}"
  end

  execute "generate and set crushmap" do
    command "osdmaptool --createsimple #{search(:node, 'recipe:ceph\:\:osd').size} --clobber /tmp/ceph-stage2/osdmap.junk --export-crush /tmp/ceph-stage2/crush.new && ceph osd setcrushmap -i /tmp/ceph-stage2/crush.new"
  end

end

# add new osd to cluster
# 
# add osd to ceph.conf
# ceph mon getmap -o /tmp/ceph-stage2/monmap
# cosd -c /etc/ceph/ceph.conf -i <osd_id> --mkfs --monmap /tmp/ceph-stage2/monmap
# cauthtool --create-keyring /tmp/ceph-stage2/keyring.osd.<osd_id>
#
# /tmp/ceph-stage2/caps:
# mds = "allow"
# mon = "allow rwx"
# osd = "allow *"
#
# cauthtool --gen-key --caps=/tmp/ceph-stage2/caps --name=osd.<osd_id> keyring.osd.<osd_id>
# ceph auth add osd.<osd_id> osd 'allow *' mon 'allow rwx' -i /path/to/osd/keyring
# ceph osd setmaxosd <osd_count>
# osdmaptool --createsimple <osd_count> --clobber /tmp/ceph-stage2/osdmap.junk --export-crush /tmp/ceph-stage2/crush.new
# ceph osd setcrushmap -i /tmp/ceph-stage2/crush.new
#
