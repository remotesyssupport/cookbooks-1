require 'base64'

include_recipe "ceph"
directory "#{node[:ceph][:mount_point]}/ceph-stage2"

["#{node[:ceph][:mount_point]}/ceph-stage2/conf", "/etc/ceph/ceph.conf"].each do |conf|                                                                                                                 
  template conf do                                                                                                                                                           
    source "ceph.conf.erb"                                                                                                                                                   
    variables(                                                                                                                                                               
      :mon => search(:node, 'recipes:ceph\:\:mon'),                                                                                                                          
      :mds => search(:node, 'recipes:ceph\:\:mds'),                                                                                                                          
      :osd => search(:node, 'recipes:ceph\:\:osd'),
      :initial_mds => search(:node, 'ceph:initial_mds')
    )
  end                                                                                                                                                                        
end                                                                                                                                                                          

service "ceph-mds" do
  service_name "ceph-mds"
  start_command "/etc/init.d/ceph start mds"
  stop_command "/etc/init.d/ceph stop mds"
  status_command "/etc/init.d/ceph status mds"
  restart_command "/etc/init.d/ceph restart mds"
end
 
template "#{node[:ceph][:mount_point]}/ceph-stage2/caps" do                                                                                                                                          
  source "caps.erb"                                                                                                                                                          
end

if search(:node, 'recipes:ceph\:\:mds').size == 1 && (search(:node, 'recipes:ceph\:\:mds').none? { |mds| mds[:ceph][:initial_mds] } || node[:ceph][:initial_mds])
  
  ruby_block "set initial mds" do
    block do
      node.set[:ceph][:initial_mds] = true
    end
    not_if { node[:ceph][:initial_mds] }
  end

  # monmap from mon node is written to <mount_point>/ceph-stage2/monmap
  if search(:node, 'recipes:ceph\:\:mon').first[:ceph][:monmap]
    file "#{node[:ceph][:mount_point]}/ceph-stage2/monmap" do
      content Base64.decode64(search(:node, 'recipes:ceph\:\:mon').first[:ceph][:monmap])
    end
  end

  # initializing mds node (by using mkcephfs), created files: key.mds.$name and keyring.mds.$name
  execute "init mds" do
    command "mkcephfs -c /etc/ceph/ceph.conf -d #{node[:ceph][:mount_point]}/ceph-stage2 --init-local-daemons mds"
    only_if { File.exists?("#{node[:ceph][:mount_point]}/ceph-stage2/monmap") && (not File.exists?("#{node[:ceph][:mount_point]}/ceph-stage2/key.mds.#{node[:hostname]}")) }
    notifies :create, "ruby_block[store mds key and keyring]", :immediately
  end

  # storing key and keyring from previous recipe
  ruby_block "store mds key and keyring" do
    action :nothing  
    block do
      key = Base64.encode64(File.read("#{node[:ceph][:mount_point]}/ceph-stage2/key.mds.#{node[:hostname]}"))
      node.set[:ceph][:mds][:key] = key
      keyring = Base64.encode64(File.read("#{node[:ceph][:mount_point]}/ceph-stage2/keyring.mds.#{node[:hostname]}"))
      node.set[:ceph][:mds][:keyring] = keyring
    end
    notifies :restart, "service[ceph-mds]"
    not_if { node[:ceph][:mds] }
  end
elsif (not node[:ceph][:initial_mds]) && search(:node, 'recipes:ceph\:\:mds').size > 1 && File.exists?("/etc/ceph/ceph.conf") && File.read("/etc/ceph/ceph.conf").include?("[osd.#{node[:ceph][:osd_id]}]")
  # expanding cluster by new mds

  # key and keyring generation
  execute "create mds key keyring" do
    command "ceph-authtool --create-keyring #{node[:ceph][:mount_point]}/ceph-stage2/keyring.mds.#{node[:hostname]} && ceph-authtool --gen-key --caps=#{node[:ceph][:mount_point]}/ceph-stage2/caps --name=mds.#{node[:hostname]} #{node[:ceph][:mount_point]}/ceph-stage2/keyring.mds.#{node[:hostname]}"
    cwd "#{node[:ceph][:mount_point]}/ceph-stage2/"
    not_if { File.exists?("#{node[:ceph][:mount_point]}/ceph-stage2/keyring.mds.#{node[:hostname]}") } 
    notifies :run, "execute[add mds to authorized machines]", :immediately
  end    
  
  # adding mds to authorized machines, based on previously generated keyring
  execute "add mds to authorized machines" do
    action :nothing
    command "ceph auth add mds.#{node[:hostname]} --in-file=#{node[:ceph][:mount_point]}/ceph-stage2/keyring.mds.#{node[:hostname]}"
    notifies :run, "execute[set mds count]"
  end

  # setting mds count at mon node
  execute "set mds count" do
    action :nothing
    command "ceph mds set_max_mds 1"
    notifies :restart, "service[ceph-mds]"
  end

end

monitrc "ceph-mds", :template => "ceph-monit", :type => "mds", :id => node[:hostname]
