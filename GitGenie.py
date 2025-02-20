import os
import subprocess
from datetime import datetime
import random
import math
import logging
import time
import json
import re
import sys
from multiprocessing import Queue
from flask import Flask

# Глобальные переменные для статистики
total_commits = 0          # Общее число успешных пушей (коммитов)
file_commit_counts = {}    # Статистика коммитов по файлам

def setup_logging():
    """
    Настраивает систему логирования
    """
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler('git_activity.log'),
            logging.StreamHandler()
        ]
    )

def get_comment(language):
    """
    Возвращает профессиональный комментарий для данного языка программирования.
    """
    comments = {
        "python": "# Refactored function for better performance",
        "sql": "-- Optimized query for faster response",
        "cpp": "// Improved memory management in loop",
        "kotlin": "// Enhanced null-safety check",
        "swift": "// Updated UI component initialization"
    }
    return comments.get(language, "# General update")

def get_language(file_path):
    """
    Определяет язык программирования файла по его расширению.
    """
    extension = os.path.splitext(file_path)[1].lower()
    if extension == ".py":
        return "python"
    elif extension == ".sql":
        return "sql"
    elif extension in [".cpp", ".hpp", ".cxx", ".h"]:
        return "cpp"
    elif extension in [".kt", ".kts"]:
        return "kotlin"
    elif extension == ".swift":
        return "swift"
    else:
        return "unknown"

def make_minimal_change(file_path, language):
    """
    Делает реалистичные изменения в коде
    """
    if not os.path.exists(file_path):
        logging.error(f"Файл {file_path} не существует!")
        return False

    try:
        with open(file_path, 'r') as f:
            content = f.readlines()

        # Гарантированно вносим изменения
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        comment = get_comment(language)
        
        # Добавляем комментарий в случайное место файла
        insert_position = random.randint(0, max(len(content), 1))
        content.insert(insert_position, f"\n{comment} - {timestamp}\n")
        
        # Сохраняем изменения
        with open(file_path, 'w') as f:
            f.writelines(content)
        
        logging.info(f"Внесено изменение в файл: {file_path}")
        return True
    except Exception as e:
        logging.error(f"Ошибка при изменении файла {file_path}: {e}")
        return False

def calculate_commits():
    """
    Вычисляет количество коммитов для репозитория, используя экспоненциальное распределение.
    """
    return 1 + min(49, math.floor(random.expovariate(1/3)))

def check_access(repo_path):
    """
    Проверяет доступность репозитория для пуша с использованием команды git push --dry-run.
    """
    try:
        subprocess.run(
            ["git", "push", "--dry-run"],
            check=True,
            cwd=repo_path,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        return True
    except subprocess.CalledProcessError as e:
        logging.error(f"Проблема доступа в репозитории {repo_path}: {e}")
        return False

def git_commit(repo_path, commit_message=None):
    """
    Вносит изменение в **один** файл, выполняет git add, commit и push в указанном репозитории.
    Возвращает словарь с информацией о том, какой файл был изменён.
    Если коммит не удался, возвращает False.
    """
    if not os.path.exists(repo_path):
        logging.error(f"Репозиторий {repo_path} не найден!")
        return False

    # Переходим в директорию репозитория
    os.chdir(repo_path)

    # Составляем список файлов с поддерживаемыми расширениями (рекурсивно)
    supported_exts = ['.py', '.sql', '.cpp', '.hpp', '.cxx', '.h', '.kt', '.kts', '.swift']
    repo_files = []
    for root, dirs, files in os.walk(repo_path):
        for file in files:
            if os.path.splitext(file)[1].lower() in supported_exts:
                repo_files.append(os.path.join(root, file))
    
    if not repo_files:
        logging.error("Нет файлов с поддерживаемыми расширениями для изменений!")
        return False

    # Выбираем ровно 1 файл для внесения изменений
    file_to_change = random.choice(repo_files)
    make_minimal_change(file_to_change, get_language(file_to_change))
    local_commit_files = {file_to_change: 1}

    # Добавляем изменения в индекс
    try:
        subprocess.run(["git", "add", "."], check=True)
        logging.info("Изменения добавлены в индекс.")
    except subprocess.CalledProcessError as e:
        logging.error(f"Ошибка при выполнении 'git add': {e}")
        return False

    # Формируем сообщение для коммита, если не задано
    if commit_message is None:
        commit_message = f"Auto-commit: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"

    # Создаём коммит
    try:
        subprocess.run(["git", "commit", "-m", commit_message], check=True)
        logging.info(f"Коммит выполнен: {commit_message}")
    except subprocess.CalledProcessError as e:
        logging.error(f"Нечего коммитить в репозитории {repo_path}: {e}")
        return False

    # Пушим изменения в удалённый репозиторий
    try:
        subprocess.run(["git", "push"], check=True)
        logging.info("Изменения отправлены в удалённый репозиторий.")
    except subprocess.CalledProcessError as e:
        logging.error(f"Ошибка при выполнении 'git push' в репозитории {repo_path}: {e}")
        return False

    # Возвращаем информацию о файле, затронутом в этом коммите
    return local_commit_files

class RepositoryStatistics:
    def __init__(self):
        self.stats_file = 'repository_stats.json'
        self.load_stats()
        
    def load_stats(self):
        """Загружает статистику из файла"""
        try:
            with open(self.stats_file, 'r') as f:
                self.stats = json.load(f)
        except FileNotFoundError:
            self.stats = {
                'repositories': {},
                'total_commits': 0,
                'commit_history': [],
                'developer_patterns': {},
                'most_active_times': {},
                'file_complexity': {},
                'commit_streaks': {
                    'current': 0,
                    'longest': 0,
                    'last_commit_date': None
                }
            }
    
    def save_stats(self):
        """Сохраняет статистику в файл"""
        with open(self.stats_file, 'w') as f:
            json.dump(self.stats, f, indent=4)
    
    def add_commit(self, repo_path, file_path, commit_type, timestamp):
        """Добавляет информацию о коммите в статистику"""
        # Статистика по репозиторию
        if repo_path not in self.stats['repositories']:
            self.stats['repositories'][repo_path] = {
                'total_commits': 0,
                'files': {},
                'last_commit': None,
                'commit_types': {},
                'active_hours': [0] * 24,
                'active_days': [0] * 7
            }
        
        repo_stats = self.stats['repositories'][repo_path]
        repo_stats['total_commits'] += 1
        repo_stats['last_commit'] = timestamp
        
        # Статистика по файлам
        if file_path not in repo_stats['files']:
            repo_stats['files'][file_path] = {
                'commits': 0,
                'last_modified': None,
                'changes_per_month': {},
                'complexity_score': 0
            }
        
        file_stats = repo_stats['files'][file_path]
        file_stats['commits'] += 1
        file_stats['last_modified'] = timestamp
        
        # Обновляем статистику по времени
        commit_hour = datetime.strptime(timestamp, '%Y-%m-%d %H:%M:%S').hour
        commit_day = datetime.strptime(timestamp, '%Y-%m-%d %H:%M:%S').weekday()
        repo_stats['active_hours'][commit_hour] += 1
        repo_stats['active_days'][commit_day] += 1
        
        # Обновляем общую статистику
        self.stats['total_commits'] += 1
        self.update_commit_streak(timestamp)
        self.save_stats()

    def update_commit_streak(self, timestamp):
        """Обновляет статистику по сериям коммитов"""
        current_date = datetime.strptime(timestamp, '%Y-%m-%d %H:%M:%S').date()
        last_date = None
        
        if self.stats['commit_streaks']['last_commit_date']:
            last_date = datetime.strptime(
                self.stats['commit_streaks']['last_commit_date'], 
                '%Y-%m-%d'
            ).date()
        
        if last_date:
            days_diff = (current_date - last_date).days
            if days_diff == 1:
                self.stats['commit_streaks']['current'] += 1
                self.stats['commit_streaks']['longest'] = max(
                    self.stats['commit_streaks']['longest'],
                    self.stats['commit_streaks']['current']
                )
            elif days_diff > 1:
                self.stats['commit_streaks']['current'] = 1
        else:
            self.stats['commit_streaks']['current'] = 1
        
        self.stats['commit_streaks']['last_commit_date'] = current_date.strftime('%Y-%m-%d')

    def calculate_file_complexity(self, file_path):
        """Рассчитывает сложность файла на основе его содержимого"""
        try:
            with open(file_path, 'r') as f:
                content = f.read()
                
            # Простой алгоритм оценки сложности
            complexity = {
                'lines': len(content.splitlines()),
                'functions': len(re.findall(r'def\s+\w+\s*\(', content)),
                'classes': len(re.findall(r'class\s+\w+\s*[:\(]', content)),
                'conditionals': len(re.findall(r'\s+if\s+', content)),
                'loops': len(re.findall(r'\s+(for|while)\s+', content))
            }
            
            # Вычисляем общий счет сложности
            score = (
                complexity['lines'] * 0.1 +
                complexity['functions'] * 2 +
                complexity['classes'] * 3 +
                complexity['conditionals'] * 1.5 +
                complexity['loops'] * 2
            )
            
            return score
        except Exception:
            return 0

    def generate_report(self):
        """Генерирует подробный отчет о статистике"""
        report = []
        report.append("\n=== Общая статистика ===")
        report.append(f"Всего коммитов: {self.stats['total_commits']}")
        report.append(f"Текущая серия коммитов: {self.stats['commit_streaks']['current']}")
        report.append(f"Самая длинная серия: {self.stats['commit_streaks']['longest']}")
        
        report.append("\n=== Статистика по репозиториям ===")
        for repo_path, repo_stats in self.stats['repositories'].items():
            report.append(f"\nРепозиторий: {repo_path}")
            report.append(f"Всего коммитов: {repo_stats['total_commits']}")
            report.append(f"Последний коммит: {repo_stats['last_commit']}")
            
            # Анализ активности по времени
            peak_hour = repo_stats['active_hours'].index(max(repo_stats['active_hours']))
            peak_day = repo_stats['active_days'].index(max(repo_stats['active_days']))
            days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']
            report.append(f"Пик активности: {peak_hour}:00, {days[peak_day]}")
            
            report.append("\nСтатистика по файлам:")
            for file_path, file_stats in repo_stats['files'].items():
                report.append(f"\n  {file_path}")
                report.append(f"  Коммитов: {file_stats['commits']}")
                report.append(f"  Последнее изменение: {file_stats['last_modified']}")
                report.append(f"  Сложность кода: {file_stats['complexity_score']:.2f}")
        
        return "\n".join(report)

def load_commit_templates():
    """Загружает шаблоны коммитов из файла"""
    templates = {
        'feature': [
            "Add {component} functionality",
            "Implement {feature} in {module}",
            "Create new {thing} system"
        ],
        'fix': [
            "Fix bug in {component}",
            "Resolve {issue} issue",
            "Patch {problem} vulnerability"
        ]
    }
    return templates

def get_realistic_commit_message(file_path, change_type):
    """
    Генерирует реалистичные сообщения коммитов на основе типа изменений и файла
    """
    file_name = os.path.basename(file_path)
    extension = os.path.splitext(file_path)[1].lower()
    
    messages = {
        'feature': [
            f"feat({extension[1:]}): implement new {file_name} functionality",
            f"feat: add {file_name} module",
            f"feature: integrate {file_name} with existing system",
            "feat: introduce dark mode support",
            "feat: add multi-language support"
        ],
        'fix': [
            f"fix({extension[1:]}): resolve memory leak in {file_name}",
            f"bugfix: handle edge case in {file_name}",
            "fix: correct validation logic",
            "hotfix: address critical performance issue",
            "fix: resolve merge conflicts"
        ],
        'refactor': [
            f"refactor({extension[1:]}): optimize {file_name} performance",
            f"refactor: clean up {file_name} implementation",
            "style: format code according to guidelines",
            "refactor: simplify error handling",
            "perf: optimize database queries"
        ],
        'docs': [
            f"docs({extension[1:]}): update {file_name} documentation",
            f"docs: add examples for {file_name}",
            "docs: fix typos in README",
            "docs: improve API documentation",
            "chore: update dependencies"
        ],
        'test': [
            f"test({extension[1:]}): add unit tests for {file_name}",
            f"test: improve coverage for {file_name}",
            "test: add integration tests",
            "test: fix flaky tests",
            "ci: configure GitHub Actions"
        ]
    }
    
    return random.choice(messages[change_type])

class HumanBehaviorSimulator:
    def __init__(self):
        self.working_hours = {
            'start': datetime.strptime('00:00', '%H:%M').time(),
            'end': datetime.strptime('23:59', '%H:%M').time()
        }
        self.lunch_time = {
            'start': datetime.strptime('13:00', '%H:%M').time(),
            'end': datetime.strptime('14:00', '%H:%M').time()
        }
        self.commit_patterns = {
            'morning_person': {'peak': 10, 'frequency': 'high'},
            'evening_person': {'peak': 16, 'frequency': 'high'},
            'steady_worker': {'peak': None, 'frequency': 'medium'}
        }
        
    def should_commit_now(self):
        """Определяет, стоит ли делать коммит в текущее время"""
        return True

    def get_commit_delay(self):
        """Возвращает задержку между коммитами в секундах"""
        base_delay = random.randint(1, 5)
        variation = random.randint(-1, 1)
        return base_delay + variation

class AIContributionEnhancer:
    def __init__(self):
        self.openai_api_key = os.getenv('OPENAI_API_KEY')
        self.github_token = os.getenv('GITHUB_TOKEN')
        
    def analyze_code_trends(self, file_path):
        """Анализирует тренды в коде и предлагает улучшения"""
        # Здесь можно добавить интеграцию с OpenAI API
        pass
        
    def generate_trending_changes(self, file_path):
        """Генерирует изменения в соответствии с текущими трендами"""
        trends = {
            '.py': ['async/await', 'type hints', 'dataclasses'],
            '.js': ['React hooks', 'TypeScript', 'Next.js'],
            '.cpp': ['modern C++', 'smart pointers', 'concepts']
        }
        extension = os.path.splitext(file_path)[1]
        return random.choice(trends.get(extension, ['general improvements']))
        
    def simulate_pair_programming(self, file_path):
        """Имитирует работу в паре с другим разработчиком"""
        # Можно добавить генерацию кода с помощью AI
        pass

class TrendingFeatures:
    def __init__(self):
        self.trends = {
            'blockchain': {
                'keywords': ['web3', 'smart contract', 'token'],
                'probability': 0.3
            },
            'ai': {
                'keywords': ['machine learning', 'neural network', 'deep learning'],
                'probability': 0.4
            },
            'cloud': {
                'keywords': ['kubernetes', 'docker', 'microservices'],
                'probability': 0.3
            }
        }
        
    def apply_trending_feature(self, file_content):
        """Добавляет модный функционал в код"""
        trend = random.choice(list(self.trends.keys()))
        if random.random() < self.trends[trend]['probability']:
            return self._inject_trending_code(file_content, trend)
        return file_content
        
    def _inject_trending_code(self, content, trend):
        """Внедряет трендовый код"""
        # Реализация внедрения кода
        pass

class TeamSimulator:
    def __init__(self):
        self.developers = {
            'frontend': {
                'languages': ['.js', '.ts', '.css', '.html'],
                'commit_style': 'feat: 🎨 {message}',
                'work_hours': (10, 19)
            },
            'backend': {
                'languages': ['.py', '.java', '.go'],
                'commit_style': 'fix: ⚡️ {message}',
                'work_hours': (9, 18)
            },
            'devops': {
                'languages': ['.yml', '.sh', '.tf'],
                'commit_style': 'ci: 🔧 {message}',
                'work_hours': (8, 17)
            }
        }
        
    def simulate_team_activity(self, repo_path):
        """Имитирует работу команды разработчиков"""
        developer = random.choice(list(self.developers.keys()))
        return self.developers[developer]

class BranchManager:
    def __init__(self):
        self.branch_types = ['feature/', 'bugfix/', 'hotfix/', 'release/']
        
    def create_branch(self, repo_path):
        """Создает новую ветку с осмысленным названием"""
        branch_type = random.choice(self.branch_types)
        branch_name = f"{branch_type}{datetime.now().strftime('%Y%m%d')}_{self._generate_feature_name()}"
        subprocess.run(['git', 'checkout', '-b', branch_name], cwd=repo_path)
        return branch_name
    
    def create_pull_request(self, repo_path, branch_name):
        """Создает PR с описанием изменений"""
        # Реализация создания PR
        pass

class CodeAnalyzer:
    def analyze_repository(self, repo_path):
        """Анализирует код и предлагает улучшения"""
        metrics = {
            'code_duplication': self._find_duplicates(repo_path),
            'complexity': self._calculate_complexity(repo_path),
            'test_coverage': self._check_test_coverage(repo_path)
        }
        return metrics
    
    def suggest_improvements(self, metrics):
        """Предлагает конкретные улучшения кода"""
        suggestions = []
        if metrics['code_duplication'] > 20:
            suggestions.append("Создать общие утилиты для повторяющегося кода")
        return suggestions

class DocumentationGenerator:
    def generate_readme(self, repo_path):
        """Создает или обновляет README.md"""
        structure = {
            'title': self._get_repo_name(repo_path),
            'description': self._analyze_repo_purpose(repo_path),
            'installation': self._generate_install_steps(repo_path),
            'usage': self._generate_usage_examples(repo_path)
        }
        return self._create_markdown(structure)

class ReleaseManager:
    def create_release(self, repo_path):
        """Создает новый релиз с changelog"""
        version = self._generate_version()
        changelog = self._generate_changelog(repo_path)
        self._create_tag(version, changelog)
        return version

class DistributedCommitSystem:
    def __init__(self):
        self.workers = []  # Список воркеров
        self.queue = Queue()  # Очередь задач
        
    def add_worker(self, worker_config):
        """Добавляет нового воркера в систему"""
        worker = CommitWorker(worker_config)
        self.workers.append(worker)
        
    def distribute_tasks(self, repositories):
        """Распределяет задачи между воркерами"""
        for repo in repositories:
            self.queue.put(repo)

class CommitAPI:
    def __init__(self):
        self.app = Flask(__name__)
        
    def setup_routes(self):
        @self.app.route('/start_commit_session', methods=['POST'])
        def start_session():
            """Запускает новую сессию коммитов"""
            pass
            
        @self.app.route('/stats', methods=['GET'])
        def get_stats():
            """Возвращает статистику коммитов"""
            pass

class CIIntegration:
    def __init__(self):
        self.ci_systems = {
            'github': GithubActions(),
            'gitlab': GitlabCI(),
            'jenkins': JenkinsCI()
        }
    
    def setup_ci(self, repo_path):
        """Настраивает CI/CD для репозитория"""
        ci_config = self._generate_ci_config()
        self._commit_ci_config(repo_path, ci_config)

class PluginSystem:
    def __init__(self):
        self.plugins = {}
        
    def load_plugins(self, plugins_dir):
        """Загружает плагины из директории"""
        for plugin_file in os.listdir(plugins_dir):
            if plugin_file.endswith('.py'):
                self._load_plugin(plugin_file)
                
    def execute_plugin(self, plugin_name, *args):
        """Выполняет плагин"""
        if plugin_name in self.plugins:
            return self.plugins[plugin_name].run(*args)

class CommitMonitor:
    def __init__(self):
        self.metrics = {}
        self.alerts = []
        
    def track_metrics(self, repo_path):
        """Отслеживает метрики коммитов"""
        self.metrics[repo_path] = {
            'commit_frequency': self._calculate_frequency(),
            'code_quality': self._analyze_quality(),
            'build_status': self._check_builds()
        }

def reset_changes(repo_path):
    """
    Сбрасывает все изменения в репозитории до последнего коммита и откатывает push
    """
    try:
        # Получаем хеш последнего коммита перед нашими изменениями
        last_commit = subprocess.run(
            ["git", "rev-parse", "HEAD~" + str(changes_made)],
            cwd=repo_path,
            capture_output=True,
            text=True,
            check=True
        ).stdout.strip()

        # Возвращаемся к предыдущему состоянию
        subprocess.run(["git", "reset", "--hard", last_commit], cwd=repo_path, check=True)
        
        # Принудительно пушим изменения
        subprocess.run(["git", "push", "--force"], cwd=repo_path, check=True)
        
        logging.info(f"Изменения в репозитории {repo_path} успешно сброшены")
        return True
    except subprocess.CalledProcessError as e:
        logging.error(f"Ошибка при сбросе изменений в репозитории {repo_path}: {e}")
        return False

def process_repositories(repositories):
    """
    Обрабатывает список репозиториев и ведет статистику
    """
    stats = RepositoryStatistics()
    global total_commits, file_commit_counts, changes_made
    changes_made = 0
    processed_repos = []  # Список обработанных репозиториев

    # Проверка доступа для каждого репозитория
    available_repos = []
    for repo_path in repositories:
        logging.info(f"\nПроверка доступа для репозитория: {repo_path}")
        if check_access(repo_path):
            available_repos.append(repo_path)
        else:
            logging.error(f"Ошибка доступа: Репозиторий {repo_path} недоступен для пуша.")

    if not available_repos:
        logging.error("Нет доступных репозиториев. Прекращаем выполнение.")
        return

    use_commit_control = input("Хотите ли вы выбрать общее количество коммитов? (да/нет): ").strip().lower()
    
    if use_commit_control == "да":
        total_commit_input = int(input("Введите общее количество коммитов: "))
        num_repos = random.randint(1, len(available_repos))
        selected_repos = random.sample(available_repos, num_repos)
        
        logging.info(f"Выбрано репозиториев: {num_repos}")
        for repo in selected_repos:
            logging.info(f"Выбран репозиторий: {repo}")
            
        remaining_commits = total_commit_input
        for i, repo_path in enumerate(selected_repos):
            if i == len(selected_repos) - 1:
                commits_this_repo = remaining_commits
            else:
                max_commits = min(remaining_commits - (len(selected_repos) - i - 1), remaining_commits - 1)
                if max_commits <= 0:
                    continue
                commits_this_repo = random.randint(1, max_commits)
                remaining_commits -= commits_this_repo

            logging.info(f"\nОбрабатывается репозиторий: {repo_path} с количеством коммитов: {commits_this_repo}")
            
            # Делаем коммиты без вопроса о сохранении
            for j in range(commits_this_repo):
                change_type = random.choice(['feature', 'fix', 'refactor', 'docs', 'test'])
                commit_message = get_realistic_commit_message(repo_path, change_type)
                
                local_commit_files = git_commit(repo_path, commit_message)
                if local_commit_files:
                    changes_made += 1
                    processed_repos.append(repo_path)
                    logging.info(f"Успешно выполнен коммит {changes_made}")
                else:
                    logging.error(f"Не удалось выполнить коммит {j+1}")
                    break
            
    else:
        num_repos = random.randint(1, len(available_repos))
        selected_repos = random.sample(available_repos, num_repos)
        
        logging.info(f"Случайно выбрано репозиториев: {num_repos}")
        for repo in selected_repos:
            logging.info(f"Выбран репозиторий: {repo}")
            
        for repo_path in selected_repos:
            commit_count_local = calculate_commits()
            logging.info(f"\nОбрабатывается репозиторий: {repo_path} с количеством коммитов: {commit_count_local}")
            
            # Делаем коммиты без вопроса о сохранении
            for i in range(commit_count_local):
                change_type = random.choice(['feature', 'fix', 'refactor', 'docs', 'test'])
                commit_message = get_realistic_commit_message(repo_path, change_type)
                
                local_commit_files = git_commit(repo_path, commit_message)
                if local_commit_files:
                    changes_made += 1
                    processed_repos.append(repo_path)
                    logging.info(f"Успешно выполнен коммит {changes_made}")
                else:
                    logging.error(f"Не удалось выполнить коммит {i+1}")
                    break

    # После всех коммитов спрашиваем один раз о сохранении
    if changes_made > 0:
        keep_changes = input("\nСохранить внесенные изменения? (да/нет): ").strip().lower()
        
        if keep_changes != 'да':
            # Откатываем изменения во всех репозиториях
            for repo_path in set(processed_repos):  # используем set для уникальных репозиториев
                if reset_changes(repo_path):
                    logging.info(f"Изменения в репозитории {repo_path} успешно отменены")
                else:
                    logging.error(f"Не удалось отменить изменения в репозитории {repo_path}")
            total_commits = 0
        else:
            total_commits = changes_made

    # Вывод итоговой статистики
    logging.info("\nСтатистика коммитов по файлам:")
    for file_path, count in file_commit_counts.items():
        logging.info(f"{file_path}: {count} коммит(ов)")
    logging.info(f"\nВсего коммитов: {total_commits}")

def main():
    """
    Основная функция программы
    """
    # Укажите здесь пути к вашим локальным репозиториям
    repositories = [
        "/Users/s2xdeb/Desktop/g/и/SQL-50-LeetCode",
        "/Users/s2xdeb/Desktop/ed_g/pythhon"
    ]
    
    while True:  # Бесконечный цикл для повторного запуска
        process_repositories(repositories)
        
        print("\nВыберите действие:")
        print("1. Показать статистику")
        print("2. Начать новую сессию")
        print("3. Выход")
        
        choice = input("Ваш выбор: ").strip()
        
        if choice == "1":
            stats = RepositoryStatistics()
            print(stats.generate_report())
        elif choice == "2":
            continue  # Продолжаем цикл, начиная новую сессию
        elif choice == "3":
            sys.exit(0)

if __name__ == "__main__":
    setup_logging()
    main()