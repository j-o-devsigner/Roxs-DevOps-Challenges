#!/bin/bash
echo "--- Lanzando los componentes de la aplicación ---"

echo "Lanzando 'result'..."
cd /home/vagrant/roxs-devops-project90/roxs-voting-app/result
npm install
npm run start &

echo "Lanzando 'worker'..."
cd /home/vagrant/roxs-devops-project90/roxs-voting-app/worker
npm install
npm run start &

echo "Lanzando 'vote'..."
cd /home/vagrant/roxs-devops-project90/roxs-voting-app/vote
sudo pip install -r requirements.txt
nohup sudo -E python3 app.py > /dev/null 2>&1 &

echo "--- ¡Aplicación lanzada! Puedes acceder a ella desde tu navegador. ---"
echo "Visita http://localhost:4999 para ver la aplicación en acción."
echo "Visita http://localhost:5001 para ver resultados de votación."
