import React from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import 'bootstrap/dist/css/bootstrap.min.css';
import 'bootstrap/dist/js/bootstrap.bundle.min.js';

import { NotificationProvider } from './contexts/NotificationContext';
import Navigation from './components/Navigation';
import DomainGroups from './components/DomainGroups';
import GroupDetails from './components/GroupDetails';
import AddGroup from './components/AddGroup';
import EditGroup from './components/EditGroup';
import IPAddresses from './components/IPAddresses';
import RouterRoutes from './components/RouterRoutes';
import SyncStatus from './components/SyncStatus';
import DnsLogs from './components/DnsLogs';

import './App.css';

function App() {
  return (
    <NotificationProvider>
      <Router>
        <div className="App">
          <Navigation />
          <div className="container mt-4">
            <Routes>
              <Route path="/" element={<DomainGroups />} />
              <Route path="/groups/add" element={<AddGroup />} />
              <Route path="/groups/:groupName/edit" element={<EditGroup />} />
              <Route path="/groups/:groupName" element={<GroupDetails />} />
              <Route path="/ip-addresses" element={<IPAddresses />} />
              <Route path="/router-routes" element={<RouterRoutes />} />
              <Route path="/sync-status" element={<SyncStatus />} />
              <Route path="/dns-logs" element={<DnsLogs />} />
            </Routes>
          </div>
        </div>
      </Router>
    </NotificationProvider>
  );
}

export default App;