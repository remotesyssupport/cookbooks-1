require 'base64'

include_recipe "ceph"
directory "/tmp/ceph-stage2"

%w(/tmp/ceph-stage2/conf /etc/ceph/ceph.conf).each do |conf|                                                                                                                 
  template conf do                                                                                                                                                           
    source "ceph.conf.erb"                                                                                                                                                   
    variables(                                                                                                                                                               
      :mon => search(:node, 'recipes:ceph\:\:mon'),                                                                                                                          
      :mds => search(:node, 'recipes:ceph\:\:mds'),                                                                                                                          
      :osd => search(:node, 'recipes:ceph\:\:osd'))
  end                                                                                                                                                                        
end                                                                                                                                                                          
 
template "/tmp/ceph-stage2/caps" do                                                                                                                                          
  source "caps.erb"                                                                                                                                                          
end

if search(:node, 'recipes:ceph\:\:mds').size == 1 
  
  ruby_block "set initial mds" do
    block do
      node.set[:ceph][:initial_mds] = true
    end
    not_if { node[:ceph][:initial_mds] }
  end

  # zapisuje sie monmap z wezla mon w folderze /tmp/ceph-stage2/monmap
  if search(:node, 'recipes:ceph\:\:mon').first[:ceph][:monmap]
    file "/tmp/ceph-stage2/monmap" do
      content Base64.decode64(search(:node, 'recipes:ceph\:\:mon').first[:ceph][:monmap])
    end
  end

  # za pomoca mkcephfs inicjalizujemy wezel mds, tworzone sa pliki key.mds.$name oraz keyring.mds.$name
  execute "init mds" do
    command "mkcephfs -c /etc/ceph/ceph.conf -d /tmp/ceph-stage2 --init-local-daemons mds"
    #not_if { File.exists?("/tmp/ceph-stage2/key.mds.*") }
    only_if { File.exists?("/tmp/ceph-stage2/monmap") && (not File.exists?("/tmp/ceph-stage2/key.mds.#{node[:hostname]}")) }
    notifies :create, "ruby_block[read key && keyring]"
  end

  # pliki utworzone podczas inicjalizacji sa zapisywane w wezle
  ruby_block "read key && keyring" do
    action :nothing  
    block do
      key = Base64.encode64(File.read("/tmp/ceph-stage2/key.mds.#{node[:hostname]}"))
      node.set[:ceph][:mds][:key] = key
      keyring = Base64.encode64(File.read("/tmp/ceph-stage2/keyring.mds.#{node[:hostname]}"))
      node.set[:ceph][:mds][:keyring] = keyring
    end
    not_if { node[:ceph][:mds] }
  end
elsif !node[:ceph][:initial_mds] && search(:node, 'recipes:ceph\:\:mds').size > 1 && File.read("/etc/ceph/ceph.conf").include?("[osd.#{node[:ceph][:osd_id]}]")

  execute "create key && keyring" do
    command "cauthtool --create-keyring /tmp/ceph-stage2/keyring.mds.#{node[:hostname]} && cauthtool --gen-key --caps=/tmp/ceph-stage2/caps --name=mds.#{node[:hostname]} /tmp/ceph-stage2/keyring.mds.#{node[:hostname]}"
  end    
  
  execute "add mds to authorized machines" do
    command "ceph auth add /tmp/cepd-stage2/mds.#{node[:hostname]} --in-file=/tmp/ceph-stage2/keyring.mds.#{node[:hostname]}"
  end

  execute "set mds count" do
    command "ceph mds set_max_mds #{search(:node, 'recipes:ceph\:\:mds').size}"
  end

end

# add new mds to cluster
#
# cauthtool --create-keyring /tmp/ceph-stage2/keyring.mds.<mds_hostname>
# /tmp/ceph-stage2/capsh:
#
# mds = "allow"
# mon = "allow rwx"
# osd = "allow *"
#
# cauthtool --gen-key --caps=/tmp/ceph-stage2/caps --name=/tmp/ceph-stage2/mds.<mds_hostname> /tmp/ceph-stage2/keyring.mds.<mds_hostname>
# ceph auth add /tmp/cepd-stage2/mds.<mds_hostname> --in-file=/tmp/ceph-stage2/keyring.mds.<mds_hostname>
# ceph mds set_max_mds <mds_count>
#
