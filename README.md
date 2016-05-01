# Topse クラウド入門コースの課題
動作確認は157.1.140.119 で行いました。

まず前提として、以下のノードが作成済みでWebサービスを運用中であり、
monitorノードによって各ノードが適切に監視されているものとします。  
    　1. deployノード  
    　2. mailノード  
    　3. dbノード  
    　4. lbノード  
    　5. monitorノード  
    　6. （1台以上の）webノード  

また、新しいWebノードにデプロイするwarについては、コミット済みとします。

/root/work/deploy/task/ 配下に、以下のスクリプトを配置する必要があります。  
    　1. deploy_and_switch_to_new_webnode.sh  
    　2. delete_old_webnode.sh  
    　3. switch_to_old_webnode.sh

デプロイサーバにログイン後、以下を実行することで、古い環境と同じ数の
Webノードを新しい環境に用意します。  
同時に、lbの振り分けを新しいWebノードに変更します。  
なお、古い環境のWebノードが２台までの場合について、動作確認を行いました。  
（それ以上の台数については動作確認未実施のため、うまく動作しないかもしれません）  
    　\# cd /root/work/deploy/task/  
    　\#./deploy_and_switch_to_new_webnode.sh

もし、古い環境へ戻して、新しい環境を破棄したい場合は、以下を実行します。  
    　\#  cd /root/work/deploy/task/  
    　\#  ./switch_to_old_webnode.sh  

新しい環境の動作確認を行い、問題がなければ、以下を実行することで、
古い環境を破棄します。  
    　\#  cd /root/work/deploy/task/  
    　\#  ./delete_old_webnode.sh  

監視と連動することも確認済みですが、反映までに若干時間がかかることがあります。

以上。


