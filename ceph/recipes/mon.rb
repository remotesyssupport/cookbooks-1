require 'base64'

include_recipe "ceph"

execute "prepare monmap" do
  mount_point = node[:ceph][:mount_point]
  command "mkcephfs -c /etc/ceph/ceph.conf -d #{node[:ceph][:mount_point]} --prepare-monmap"
  only_if { File.read("/etc/ceph/ceph.conf").include?("[mon.#{node[:hostname]}]") }
  not_if { File.exists?("#{node[:ceph][:mount_point]}/monmap") }
  notifies :create, "ruby_block[read monmap]"
end

ruby_block "read monmap" do
  action :nothing
  block do
    monmap = Base64.encode64(File.read("#{node[:ceph][:mount_point]}/monmap"))
    node.set[:ceph][:monmap] = monmap
  end
  not_if { node[:ceph][:monmap] && File.exists?("#{node[:ceph][:mount_point]}/monmap") }
end


%w(mds osd).each do |node_type|
  search(:node, "recipes:ceph\:\:#{node_type}").each do |host| 
    if host[:ceph][node_type]
      %w(key keyring).each do |type|
        node_id = node_type == "mds" ? host[:hostname] : host[:ceph][:osd_id]
        file "/srv/#{type}.#{node_type}.#{node_id}" do
          content host[:ceph][node_type][type.to_sym]
          notifies :run, "execute[prepare mon]"
          notifies :run, "execute[init mon]"
        end
      end
    end
  end
end

execute "prepare mon" do
  action :nothing
  command "mkcephfs -d #{node[:ceph][:mount_point]} --prepare-mon"
  returns [0, 1, 255]
end

execute "init mon" do 
  action :nothing
  command "mkcephfs -d /srv --init-local-daemons mon"
end
