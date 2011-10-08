module Ceph

  def osd_fullyconfigured?
    search(:node, 'recipes:ceph\:\:osd').any? { |osd| osd[:ceph][:osd] && osd[:ceph][:osd][:key] && osd[:ceph][:osd][:keyring] }
  end

  def mds_fullyconfigured?
    search(:node, 'recipes:ceph\:\:mds').any? { |mds| mds[:ceph][:mds] && mds[:ceph][:mds][:key] && mds[:ceph][:mds][:keyring] }
  end

end
