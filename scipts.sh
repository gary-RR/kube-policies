#!/bin/bash

ssh YOUR_ID@YOUR_KUBE_NODE
#***********************************************variables*********************************************
declare UI_POD_NAME;
declare BUS_POD_NAME;
declare DB_POD_NAME;
declare ProductsUIClusterIP;
declare ProductsBusinessClusterIP;
declare ProductsDBClusterIP;
declare POD_BUSINESS_STAGE_NS;
declare POD_UI_STAGE_N;

function setup_env(){
   

    kubectl create namespace products-prod 
    kubectl create namespace products-stage 

    #Deploy PODs to products-prod name space
    kubectl create deployment products-ui -n products-prod --image=gcr.io/google-samples/hello-app:1.0 
    kubectl create deployment products-business -n products-prod --image=gcr.io/google-samples/hello-app:1.0 
    kubectl create deployment products-db -n products-prod --image=gcr.io/google-samples/hello-app:1.0

    #Create services for our deployments
    kubectl expose deployment products-ui -n products-prod --port=8080 --target-port=8080 --type=NodePort 
    kubectl expose deployment products-business -n products-prod --port=8080 --target-port=8080 --type=NodePort 
    kubectl expose deployment products-db -n products-prod --port=8080 --target-port=8080 --type=NodePort 

    #Deploy PODs to products-stage name space
    kubectl create deployment products-ui --image=gcr.io/google-samples/hello-app:1.0 -n products-stage
    kubectl create deployment products-business --image=gcr.io/google-samples/hello-app:1.0 -n products-stage

    #Get the POD names for the UI, Business, and Databse tiers (products-prod name space)
    kubectl get pods -n products-prod
    UI_POD_NAME=$(kubectl get pods -n products-prod | awk '  NR>1 { print $1}' | grep products-ui)
    BUS_POD_NAME=$(kubectl get pods -n products-prod | awk '  NR>1 { print $1}' | grep products-business)
    DB_POD_NAME=$(kubectl get pods -n products-prod | awk '  NR>1 { print $1}' | grep products-db)

    #Get the POD names for the UI, and Business tiers (products-stage name space)
    BUS_POD_NAME_STAGE=$(kubectl get pods -n products-stage | awk '  NR>1 { print $1}' | grep products-business)
    UI_POD_NAME_STAGE=$(kubectl get pods -n products-stage | awk '  NR>1 { print $1}' | grep products-ui)

    #Get the Cluster IPs
    kubectl get services -o wide -n products-prod 
    #Get "products-ui" ClusterIP
    ProductsUIClusterIP=$(kubectl get service products-ui -n products-prod -o jsonpath='{ .spec.clusterIP }')
    #Get "products-business" ClusterIP
    ProductsBusinessClusterIP=$(kubectl get service products-business -n products-prod -o jsonpath='{ .spec.clusterIP }')
    #Get "products-db" ClusterIP
    ProductsDBClusterIP=$(kubectl get service products-db -n products-prod -o jsonpath='{ .spec.clusterIP }')

}

#************Network Policy Part One: Restrict access to DB POD, allow access from "Stage" NS, and restrict DB egress access*****  

setup_env

#Test from services on various tiers from node
curl --max-time 1.5  http://$ProductsUIClusterIP:8080
curl --max-time 1.5  http://$ProductsBusinessClusterIP:8080
curl --max-time 1.5  http://$ProductsDBClusterIP:8080

#Test from services on various tiers from inside PODs
kubectl exec -it $UI_POD_NAME -n products-prod -- wget -q --timeout=2 http://$ProductsBusinessClusterIP:8080 -O -  
kubectl exec -it $UI_POD_NAME -n products-prod -- wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O -  
kubectl exec -it $BUS_POD_NAME -n products-prod -- wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O - 

kubectl exec -it $UI_POD_NAME_STAGE -n products-stage -- wget -q --timeout=2 http://$ProductsBusinessClusterIP:8080 -O -
kubectl exec -it $UI_POD_NAME_STAGE -n products-stage -- wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O - 
kubectl exec -it $BUS_POD_NAME_STAGE -n products-stage -- wget -q --timeout=2 http://$ProductsBusinessClusterIP:8080 -O - 
kubectl exec -it $BUS_POD_NAME_STAGE -n products-stage -- wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O - 

#Apply network policies to restrict ingress access to Business and DB PODs   

    kubectl apply -f restrict-access-to-ui-tier-only.yaml -n products-prod

    kubectl apply -f restrict-access-to-business-tier-only.yaml -n products-prod

    #Test again 
    kubectl exec -it $UI_POD_NAME -n products-prod -- wget -q --timeout=2 http://$ProductsBusinessClusterIP:8080 -O -  
    kubectl exec -it $UI_POD_NAME -n products-prod -- wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O -  
    kubectl exec -it $BUS_POD_NAME -n products-prod -- wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O - 
    
    kubectl exec -it $UI_POD_NAME_STAGE -n products-stage -- wget -q --timeout=2 http://$ProductsBusinessClusterIP:8080 -O -
    kubectl exec -it $UI_POD_NAME_STAGE -n products-stage -- wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O - 
    kubectl exec -it $BUS_POD_NAME_STAGE -n products-stage -- wget -q --timeout=2 http://$ProductsBusinessClusterIP:8080 -O - 
    kubectl exec -it $BUS_POD_NAME_STAGE -n products-stage -- wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O - 

#Apply network policy to allow stage business POD access db POD in prod
    #Label stage name spacese
    kubectl label namespace products-stage porducts-prod-db-access=allow

    #Apply the policy
    kubectl apply -f allow-stage-business-tier-access-to-db.yaml
    
    #Retest 
    kubectl exec -it $UI_POD_NAME_STAGE -n products-stage -- wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O -
    kubectl exec -it $BUS_POD_NAME_STAGE -n products-stage -- wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O -
    

#Check if DB POD has egress access to outside cluster 
kubectl exec -it $DB_POD_NAME -n products-prod -- wget -q --timeout=2 http://10.0.0.24:8080/computer -O -

#Restrict egress "db" POD traffic to POD network  
    kubectl apply -f restrict-db-egress-traffic-to-cluster-only.yaml
    #Retest
    kubectl exec -it $DB_POD_NAME -n products-prod -- wget -q --timeout=2 http://10.0.0.24:8080/computer -O -
    kubectl exec -it $DB_POD_NAME -n products-prod -- nslookup google.com
    kubectl exec -it $DB_POD_NAME -n products-prod -- wget -q --timeout=2 http://google.com -O -
    kubectl exec -it $DB_POD_NAME -n products-prod -- wget -q --timeout=2 http://$ProductsUIClusterIP:8080 -O -

#Cleanup
cleanup
#**********************************************************************************************************

#************************************Advanced Policies*************************************************************
setup_env

curl --max-time 1.5  http://$ProductsUIClusterIP:8080

#Creat a default egress deny network policy
kubectl apply -f default-deny-ingress.yaml -n products-prod

#Check we can access the UI service from node
curl --max-time 1.5  http://$ProductsUIClusterIP:8080

#Allow ingress access from within the cluster to UI
    kubectl apply -f allow-ingres-traffic-from-cluster-to-ui.yaml

    #Check again if we can access the UI service from node
    curl --max-time 1.5  http://$ProductsUIClusterIP:8080

#Check if UI POD has access to Business POD
kubectl exec -it $UI_POD_NAME -n products-prod -- wget -q --timeout=2 http://$ProductsBusinessClusterIP:8080 -O -

#Give UI POD access to Business POD
    kubectl apply -f allow-ui-tier-access-to-business.yaml 

    #Check again
    kubectl exec -it $UI_POD_NAME -n products-prod -- wget -q --timeout=2 http://$ProductsBusinessClusterIP:8080 -O -
    #Check we can access the business service from node
    curl --max-time 1.5  http://$ProductsBusinessClusterIP:8080


#Check if Business POD has access to DB POD
kubectl exec -it $BUS_POD_NAME -n products-prod -- wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O -

#Give Business POD access to Business POD
    kubectl apply -f allow-business-tier-access-to-db.yaml 
    #Check again
    kubectl exec -it $BUS_POD_NAME -n products-prod -- wget -q --timeout=2 http://$ProductsDBClusterIP:8080 -O -

#----------------------------------Egress--------------------------------------------

#Set to deny egress efault
kubectl apply -f default-deny-egress.yaml

#Try to call a service from one of the PODs
kubectl exec -it $UI_POD_NAME -n products-prod -- wget -q --timeout=2 http://$ProductsBusinessClusterIP:8080 -O -

#Check if DNS resolution is available (kube-proxy) 
kubectl exec -it $UI_POD_NAME -n products-prod -- nslookup google.com

#Enable DNS access
    #Label kube-system
    kubectl label namespace kube-system name=kube-system
    kubectl apply -f allow-dns-access.yaml
    #Check again
    kubectl exec -it $UI_POD_NAME -n products-prod -- nslookup google.com

#Enable egress acces to cluster
    kubectl apply -f allow-products-prod-egress-traffic-to-cluster.yaml
    #Try again
    kubectl exec -it $UI_POD_NAME -n products-prod -- wget -q --timeout=2 http://$ProductsBusinessClusterIP:8080 -O -
    #Chek if it has intranet access
    kubectl exec -it $UI_POD_NAME -n products-prod -- wget -q --timeout=2 http://10.0.0.24:8080/computer -O -

#Cleanup
cleanup
#*********************************************************************************************************************

function cleanup(){        
    kubectl delete namespace products-stage;
    kubectl delete namespace products-prod
}




