#!/usr/bin/env python3
"""
DolphinDB 云平台管理器
提供 REST API 用于创建/删除用户环境
"""
from flask import Flask, request, jsonify
import subprocess
import json
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

class DolphinDBPlatform:
    def __init__(self, helm_chart_path='./dolphindb-user-chart'):
        self.helm_chart = helm_chart_path
    
    def create_workspace(self, user_id, config=None):
        """创建用户工作空间"""
        try:
            # 默认配置
            default_config = {
                'userId': user_id,
                'dolphindb': {
                    'storage': '10Gi',
                    'username': 'admin',
                    'password': 'changeme'
                },
                'codeserver': {
                    'password': 'userpassword'
                }
            }
            
            if config:
                default_config.update(config)
            
            # 使用 Helm 创建
            release_name = f'dolphindb-{user_id}'
            
            # 构建 helm install 命令
            cmd = [
                'helm', 'install', release_name, self.helm_chart,
                '--set', f'userId={user_id}',
                '--set', f'dolphindb.password={default_config["dolphindb"]["password"]}',
                '--set', f'codeserver.password={default_config["codeserver"]["password"]}',
                '--set', f'dolphindb.storage={default_config["dolphindb"]["storage"]}',
                '--wait',
                '--timeout', '5m'
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                logging.info(f"✓ Created workspace for {user_id}")
                return {
                    'success': True,
                    'userId': user_id,
                    'url': f'//{user_id}',
                    'message': 'Workspace created successfully'
                }
            else:
                logging.error(f"✗ Failed to create workspace: {result.stderr}")
                return {
                    'success': False,
                    'error': result.stderr
                }
                
        except Exception as e:
            logging.error(f"Exception: {str(e)}")
            return {
                'success': False,
                'error': str(e)
            }
    
    def delete_workspace(self, user_id):
        """删除用户工作空间"""
        try:
            release_name = f'dolphindb-{user_id}'
            
            cmd = ['helm', 'uninstall', release_name]
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                logging.info(f"✓ Deleted workspace for {user_id}")
                return {
                    'success': True,
                    'userId': user_id,
                    'message': 'Workspace deleted successfully'
                }
            else:
                return {
                    'success': False,
                    'error': result.stderr
                }
                
        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }
    
    def list_workspaces(self):
        """列出所有工作空间"""
        try:
            cmd = ['helm', 'list', '-o', 'json']
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                releases = json.loads(result.stdout)
                workspaces = [
                    {
                        'userId': r['name'].replace('dolphindb-', ''),
                        'status': r['status'],
                        'updated': r['updated']
                    }
                    for r in releases
                    if r['name'].startswith('dolphindb-')
                ]
                return {
                    'success': True,
                    'workspaces': workspaces
                }
            else:
                return {
                    'success': False,
                    'error': result.stderr
                }
                
        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }
    
    def get_workspace_status(self, user_id):
        """获取工作空间状态"""
        try:
            release_name = f'dolphindb-{user_id}'
            
            cmd = ['helm', 'status', release_name, '-o', 'json']
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                status = json.loads(result.stdout)
                return {
                    'success': True,
                    'status': status
                }
            else:
                return {
                    'success': False,
                    'error': 'Workspace not found'
                }
                
        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }


# 创建平台实例
platform = DolphinDBPlatform()

# REST API 端点
@app.route('/api/v1/workspaces', methods=['POST'])
def create_workspace():
    """创建工作空间"""
    data = request.json
    user_id = data.get('userId')
    
    if not user_id:
        return jsonify({'error': 'userId is required'}), 400
    
    result = platform.create_workspace(user_id, data.get('config'))
    
    if result['success']:
        return jsonify(result), 201
    else:
        return jsonify(result), 500

@app.route('/api/v1/workspaces/<user_id>', methods=['DELETE'])
def delete_workspace(user_id):
    """删除工作空间"""
    result = platform.delete_workspace(user_id)
    
    if result['success']:
        return jsonify(result), 200
    else:
        return jsonify(result), 500

@app.route('/api/v1/workspaces', methods=['GET'])
def list_workspaces():
    """列出所有工作空间"""
    result = platform.list_workspaces()
    
    if result['success']:
        return jsonify(result), 200
    else:
        return jsonify(result), 500

@app.route('/api/v1/workspaces/<user_id>', methods=['GET'])
def get_workspace_status(user_id):
    """获取工作空间状态"""
    result = platform.get_workspace_status(user_id)
    
    if result['success']:
        return jsonify(result), 200
    else:
        return jsonify(result), 404

@app.route('/health', methods=['GET'])
def health():
    """健康检查"""
    return jsonify({'status': 'healthy'}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)