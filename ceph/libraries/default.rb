module Ceph

  def osd_fullyconfigured?
    node[:ceph][:osd] && node[:ceph][:osd][:key] && node[:ceph][:osd][:keyring]
  end

  def mds_fullyconfigured?
    node[:ceph][:mds] && node[:ceph][:mds][:key] && node[:ceph][:mds][:keyring]
  end

end
