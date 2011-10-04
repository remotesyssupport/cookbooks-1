require 'base64'

include_recipe "ceph"

execute "prepare monmap" do
  mount_point = node[:ceph][:mount_point]
  command "mkcephfs -c /etc/ceph/ceph.conf -d #{node[:ceph][:mount_point]} --prepare-monmap"
  not_if { File.exists?("#{node[:ceph][:mount_point]}/monmap") }
end

ruby_block "read monmap" do
  block do
    monmap = Base64.encode64(File.read("#{node[:ceph][:mount_point]}/monmap"))
    node.set[:ceph][:monmap] = monmap
  end
  not_if { node[:ceph][:monmap] }
end

execute "prepare mon" do
  command "mkcephfs -d #{node[:ceph][:mount_point]} --prepare-mon"
  keyring = Base64.encode64(File.read("#{node[:ceph][:mount_point]}/keyring.admin"))
  node.set[:ceph][:mon][:keyring] = keyring
  not_if { File.exists?("#{node[:ceph][:mount_point]}/keyring.admin") }
end

%w(mds osd).each do |node_type|
  search(:node, 'recipes:ceph\:\:'+ node_type).each do |host| 
    %w(key keyring).each do |type|
      node_id = node_type == "mds" ? host[:hostname] : host[:ceph][:osd_id]
      file "/srv/#{type}.#{node_type}.#{node_id}" do
        content host[:ceph][node_type.to_sym][type.to_sym]
        notifies :run, "execute[init mon]"
      end
    end
  end
end

execute "init mon" do 
  action :nothing
  command "mkcephfs -d /srv --init-local-daemons mon"
end

file "/etc/ceph/keyring" do
  content Base64.decode64(node[:ceph][:mon][:keyring])
end
