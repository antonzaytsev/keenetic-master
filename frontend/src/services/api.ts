import axios from 'axios';

const API_BASE_URL = `http://${process.env.REACT_APP_API_BASE_HOST}:${process.env.REACT_APP_API_BASE_PORT}`;

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

export interface Domain {
  id: number;
  domain: string;
  type: 'regular' | 'follow_dns';
}

export interface GroupDomainsResponse {
  group_id: number;
  group_name: string;
  domains: Domain[];
  statistics: {
    total: number;
    regular: number;
    follow_dns: number;
  };
}

export interface DomainGroup {
  id: number;
  name: string;
  mask?: string;
  interfaces?: string;
  domains: any;
  statistics: {
    total_domains: number;
    regular_domains: number;
    follow_dns_domains: number;
    total_routes: number;
    synced_routes: number;
    pending_routes: number;
    last_updated?: string;
  };
  created_at?: string;
  updated_at?: string;
}

export interface Route {
  id: number;
  network: string;
  mask: string;
  interface?: string;
  comment?: string;
  group_name?: string;
  synced_to_router: boolean;
  synced_at?: string;
  created_at?: string;
  updated_at?: string;
}

export interface SyncLog {
  id: number;
  operation: string;
  resource_type: string;
  resource_id?: number;
  success: boolean;
  error_message?: string;
  created_at?: string;
}

export interface SyncStats {
  total_routes: number;
  synced_routes: number;
  pending_sync: number;
  stale_routes: number;
}

export interface SyncStatusData {
  statistics: SyncStats;
  recent_logs: SyncLog[];
  recent_failures: SyncLog[];
}

export interface DnsLog {
  id: number;
  action: string;
  domain: string;
  group_name: string;
  network?: string;
  mask?: string;
  interface?: string;
  comment?: string;
  ip_addresses: string[];
  routes_count: number;
  created_at: string;
}

export interface DnsLogsResponse {
  logs: DnsLog[];
  pagination: {
    page: number;
    per_page: number;
    total_count: number;
    total_pages: number;
  };
}

export interface DnsLogsStats {
  total_logs: number;
  recent_24h: number;
  by_action: { [key: string]: number };
  by_group: { [key: string]: number };
  total_routes_processed: number;
}

export interface DnsLogsStatsResponse {
  statistics: DnsLogsStats;
  recent_activity: DnsLog[];
}

// API Functions
export const apiService = {
  // Domain Groups
  getDomainGroups: async (): Promise<DomainGroup[]> => {
    const response = await api.get('/api/domain-groups');
    return response.data;
  },

  getDomainGroup: async (name: string): Promise<any> => {
    const response = await api.get(`/api/domains/${name}`);
    return response.data;
  },

  createDomainGroup: async (name: string, data: any): Promise<any> => {
    const response = await api.post(`/api/domains/${name}`, data);
    return response.data;
  },

  updateDomainGroup: async (name: string, data: any): Promise<any> => {
    const response = await api.post(`/api/domains/${name}`, data);
    return response.data;
  },

  updateDomainGroupById: async (id: number, data: { name?: string; mask?: string; interfaces?: string }): Promise<any> => {
    const response = await api.put(`/api/domain-groups/${id}`, data);
    return response.data;
  },

  deleteDomainGroup: async (name: string): Promise<any> => {
    const response = await api.delete(`/api/domains/${name}`);
    return response.data;
  },

  getGroupDomains: async (groupId: number): Promise<GroupDomainsResponse> => {
    const response = await api.get(`/api/domain-groups/${groupId}/domains`);
    return response.data;
  },

  addDomainToGroup: async (groupId: number, domain: string, type: 'regular' | 'follow_dns' = 'regular'): Promise<any> => {
    const response = await api.post(`/api/domain-groups/${groupId}/domains`, { domain, type });
    return response.data;
  },

  deleteDomainFromGroup: async (groupId: number, domain: string, type: 'regular' | 'follow_dns' = 'regular'): Promise<any> => {
    const encodedDomain = encodeURIComponent(domain);
    const response = await api.delete(`/api/domain-groups/${groupId}/domains/${encodedDomain}?type=${type}`);
    return response.data;
  },

  // Group operations
  getRouterRoutes: async (groupName: string): Promise<any> => {
    const response = await api.get(`/api/domains/${groupName}/router-routes`);
    return response.data;
  },

  getAllRouterRoutes: async (params?: {
    interface?: string;
    proto?: string;
    network?: string;
  }): Promise<any> => {
    const response = await api.get('/api/router-routes', { params });
    return response.data;
  },

  getRouterInterfaces: async (): Promise<any> => {
    const response = await api.get('/api/router-interfaces');
    return response.data;
  },

  // IP Addresses / Routes
  getRoutes: async (params?: {
    sync_status?: string;
    group_id?: string;
  }): Promise<Route[]> => {
    const response = await api.get('/api/ip-addresses', { params });
    return response.data;
  },

  // Sync Status
  getSyncStats: async (): Promise<SyncStatusData> => {
    const response = await api.get('/api/sync-stats');
    return response.data;
  },

  getSyncLogs: async (params?: {
    page?: number;
    per_page?: number;
  }): Promise<{
    logs: SyncLog[];
    pagination: {
      page: number;
      per_page: number;
      total_count: number;
      total_pages: number;
    };
  }> => {
    const response = await api.get('/api/sync-logs', { params });
    return response.data;
  },

  // DNS Logs
  getDnsLogs: async (params?: {
    page?: number;
    per_page?: number;
    action?: string;
    group_name?: string;
    domain?: string;
    search?: string;
    start_date?: string;
    end_date?: string;
  }): Promise<DnsLogsResponse> => {
    const response = await api.get('/api/dns-logs', { params });
    return response.data;
  },

  getDnsLogsStats: async (): Promise<DnsLogsStatsResponse> => {
    const response = await api.get('/api/dns-logs/stats');
    return response.data;
  },

  // Health check
  getHealth: async (): Promise<any> => {
    const response = await api.get('/health');
    return response.data;
  },

  // Dumps
  dumpDatabase: async (): Promise<any> => {
    const response = await api.get('/api/dumps/database');
    return response.data;
  },

  importDatabase: async (dumpData: any, clear: boolean = false): Promise<any> => {
    const response = await api.post('/api/dumps/database/import', dumpData, {
      params: { clear: clear.toString() }
    });
    return response.data;
  },

  dumpRouterRoutes: async (): Promise<any> => {
    const response = await api.get('/api/dumps/router-routes');
    return response.data;
  },

  importRouterRoutes: async (dumpData: any): Promise<any> => {
    const response = await api.post('/api/dumps/router-routes/import', dumpData);
    return response.data;
  },
};

export default apiService;
