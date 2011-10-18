require 'base64'

include_recipe "ceph"

class Chef::Recipe; include Ceph end

template "/etc/ceph/ceph.conf" do
  source "ceph.conf.erb"
  variables(
    :mon => search(:node, 'recipes:ceph\:\:mon'),
    :mds => search(:node, 'recipes:ceph\:\:mds'),
    :osd => search(:node, 'recipes:ceph\:\:osd'),
    :initial_mds => search(:node, 'ceph:initial_mds')
  )
  notifies :restart, "service[ceph-mon]"
end

service "ceph-mon" do
  service_name "ceph-mon"
  start_command "/etc/init.d/ceph start mon"
  stop_command "/etc/init.d/ceph stop mon"
  status_command "/etc/init.d/ceph status mon"
  restart_command "/etc/init.d/ceph restart mon"
end

if (not node[:ceph][:initial_mon]) && (not initial_mon_exists?)
  # generating :mount_point/monmap file (by using mkcephfs), based on /etc/ceph/ceph.conf file
  execute "prepare monmap" do
    mount_point = node[:ceph][:mount_point]
    command "mkcephfs -c /etc/ceph/ceph.conf -d #{node[:ceph][:mount_point]} --prepare-monmap"
    only_if { File.read("/etc/ceph/ceph.conf").include?("[mon.#{node[:hostname]}]") && (not File.exists?("#{node[:ceph][:mount_point]}/monmap")) }
    notifies :create, "ruby_block[store monmap]", :immediately
  end

  # storing :mount_point/monmap file at node
  ruby_block "store monmap" do
    action :nothing
    block do
      monmap = Base64.encode64(File.read("#{node[:ceph][:mount_point]}/monmap"))
      node.set[:ceph][:monmap] = monmap
    end
    not_if { node[:ceph][:monmap] && File.exists?("#{node[:ceph][:mount_point]}/monmap") }
  end


  osd_nodes = search(:node, "recipes:ceph\\:\\:osd")
  mds_nodes = search(:node, "recipes:ceph\\:\\:mds")
  minimal_cluster_exists = osd_nodes.length == 1 && mds_nodes.length == 1

  # at this moment osd and mon have to be fully configured
  # this step is necessary only in case of initial cluster configuration 
  if osd_fullyconfigured? && mds_fullyconfigured? && minimal_cluster_exists
    
    # storing key and keyring for each osd and mds at mon node
    %w(mds osd).each do |node_type|
      search(:node, "recipes:ceph\\:\\:#{node_type}").each do |host| 
        if host[:ceph][node_type]
          %w(key keyring).each do |type|
            node_id = node_type == "mds" ? host[:hostname] : host[:ceph][:osd_id]
            file "#{node[:ceph][:mount_point]}/#{type}.#{node_type}.#{node_id}" do
              content host[:ceph][node_type][type.to_sym]
            end
          end
        end
      end
    end

    # generating :mount_point/{osdmap,keyring.admin} files
    # mkcephfs can exit abnormally even with task is successful
    execute "prepare mon" do
      command "mkcephfs -d #{node[:ceph][:mount_point]} --prepare-mon"
      returns [0, 1, 255]
      not_if { File.exists?("#{node[:ceph][:mount_point]}/osdmap") }
    end

    # generating :mount_point/mon file
    execute "init mon" do 
      command "mkcephfs -d #{node[:ceph][:mount_point]} --init-local-daemons mon"
      not_if { File.exists?("#{node[:ceph][:mount_point]}/mon") }
      notifies :restart, "service[ceph-mon]"
      notifies :create, "ruby_block[set initial mon]"
    end
  end
  
  ruby_block "set initial mon" do
    block do
      node.set[:ceph][:initial_mon] = true
    end
    action :nothing
  end

elsif initial_mon_exists? && get_initial_mon[:hostname] != node[:hostname]
  execute "expanding cluster" do
    command "echo 1 > /tmp/qq"
  end
      
  snapshot = data_bag_item("ceph", "mon_snapshot")    

  # store snapshot
  if snapshot
    file "/tmp/mon_snapshot.tar.xz" do
      content Base64.decode64(snapshot["data"])
    end
  end

  execute "unpack snapshot" do
    command "tar xJfv /tmp/mon_snapshot.tar.xz -C #{node[:ceph][:mount_point]}"
    only_if { File.exists?("/tmp/mon_snapshot.tar.xz") }
    notifies :restart, "service[ceph-mon]"
  end

elsif initial_mon_exists? && node[:ceph][:initial_mon] && active_monitors_count < search(:node, "recipes:ceph\\:\\:mon").size
 
  # execute ceph mon add for each new monitor
  search(:node, "recipes:ceph\\:\\:mon").each do |e|
    if not get_active_monitors.include?(e[:hostname])
      execute "add #{e[:hostname]} monitor" do
        command "ceph mon add #{e[:hostname]} #{e[:ipaddress]}:6789"
        notifies :restart, "service[ceph-mon]"
      end
    end
  end

end
