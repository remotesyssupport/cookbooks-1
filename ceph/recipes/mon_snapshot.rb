require 'base64'

include_recipe 'ceph'

if node[:ceph][:initial_mon]

  execute "prepare mon_snapshot" do
    command "cd /srv && tar -cJf #{node[:ceph][:mount_point]}/mon_snapshot.tar.xz mon"
  end 
  
  # DOESN'T WORK NEED FIX (requires chef 0.10.4)
  # cd /srv && tar -cJf #{node[:ceph][:mount_point]}/mon_snapshot.tar.xz mon
  # Base64.encode64(File.open("#{node[:ceph][:mount_point]}/mon_snapshot"))
  # paste to file
  # knife data bag upload from file ceph mon_snapshot
  ruby_block "store snapshot" do
    #snapshot = Chef::DataBag.new
    #snapshot.name("mon_snapshot")
    #snapshot.save

    data = {
      "id" => node[:hostname],
      "timestamp" => Date.new,
      "file" => Base64.encode64(File.read("#{node[:ceph][:mount_point]}/mon_snapshot.tar.xz"))
    }

    snapshot_item = Chef::DataBagItem.new
    snapshot_item.data_bag("ceph")
    snapshot_item.raw_data = data
    snapshot_item.save

    only_if { File.exists?("#{node[:ceph][:mount_point]}/mon_snapshot.tar.xz") }
  end

end
