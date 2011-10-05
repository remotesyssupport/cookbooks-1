require 'base64'

ruby_block "set osd id" do
  block do
    node.set[:ceph][:osd_id] = search(:node, 'recipes:ceph\:\:osd').size
  end
  not_if { node[:ceph][:osd_id] } 
end

if search(:node, 'recipes:ceph\:\:osd').any? { |osd| osd[:hostname] == node[:hostname] } && node[:ceph][:osd_id]
  include_recipe "ceph"
  directory "/tmp/ceph-stage2"

  template "/tmp/ceph-stage2/conf" do
    source "ceph.conf.erb"
    variables(
      :mon => search(:node, 'recipes:ceph\:\:mon'),
      :mds => search(:node, 'recipes:ceph\:\:mds'),
      :osd => search(:node, 'recipes:ceph\:\:osd')
    )
  end

  if search(:node, 'recipes:ceph\:\:mon').first[:ceph][:monmap]
    file "/tmp/ceph-stage2/monmap" do
      content Base64.decode64(search(:node, 'recipes:ceph\:\:mon').first[:ceph][:monmap])
    end
  end

  execute "init osd" do
    command "mkcephfs -c /etc/ceph/ceph.conf -d /tmp/ceph-stage2 --init-local-daemons osd"
    not_if { File.exists?("/tmp/ceph-stage2/key.osd.*") }
    only_if { File.exists?("/tmp/ceph-stage2/monmap") }
    notifies :create, "ruby_block[read key && keyring]"
  end

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
end

