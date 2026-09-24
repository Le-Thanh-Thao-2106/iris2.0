-- =====================================================================
-- IRIS SVM - COMPLETE SUPABASE SQL SCHEMA & RLS POLICIES
-- Hướng dẫn: Mở Supabase Dashboard -> SQL Editor -> Dán toàn bộ script này -> Nhấn "RUN"
-- =====================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. ENUM FOR ROLES
DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('USER', 'ADMIN');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 3. PROFILES TABLE (Gắn liền với Supabase Auth)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    full_name TEXT,
    role user_role DEFAULT 'USER'::user_role NOT NULL,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- 4. USER PREFERENCES (Lưu cấu hình mặc định/lần dùng gần nhất của từng user)
CREATE TABLE IF NOT EXISTS public.user_preferences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    selected_kernel TEXT DEFAULT 'rbf' NOT NULL,
    selected_c NUMERIC DEFAULT 1.0 NOT NULL,
    selected_gamma NUMERIC DEFAULT 0.1 NOT NULL,
    selected_degree INT DEFAULT 3 NOT NULL,
    selected_features JSONB DEFAULT '["Petal Length", "Petal Width"]'::jsonb NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- 5. PREDICTION HISTORY (Lịch sử nhận diện từng mẫu hoa của user)
CREATE TABLE IF NOT EXISTS public.prediction_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    sepal_length NUMERIC NOT NULL,
    sepal_width NUMERIC NOT NULL,
    petal_length NUMERIC NOT NULL,
    petal_width NUMERIC NOT NULL,
    prediction TEXT NOT NULL, -- 'setosa', 'versicolor', 'virginica'
    confidence NUMERIC DEFAULT 100.0,
    method TEXT DEFAULT 'Nhập số liệu' NOT NULL, -- 'Nhập số liệu', 'Click biểu đồ', 'Đoán thử thách', 'File CSV'
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- 6. EXPERIMENT HISTORY (Lịch sử các lần huấn luyện & thí nghiệm SVM)
CREATE TABLE IF NOT EXISTS public.experiment_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    kernel TEXT NOT NULL, -- 'linear', 'rbf', 'poly', 'sigmoid', 'precomputed'
    c_param NUMERIC NOT NULL,
    gamma_param NUMERIC NOT NULL,
    degree INT DEFAULT 3,
    features JSONB NOT NULL,
    feature_indices JSONB NOT NULL,
    accuracy NUMERIC NOT NULL,
    train_accuracy NUMERIC,
    precision NUMERIC,
    recall NUMERIC,
    f1_score NUMERIC,
    support_vector_count INT DEFAULT 0,
    execution_time_ms NUMERIC NOT NULL,
    note TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- 7. APP CONTENT (Lưu nội dung bài viết Giới thiệu do Admin quản lý)
CREATE TABLE IF NOT EXISTS public.app_content (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    key TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- 8. INDEXES FOR PERFORMANCE
CREATE INDEX IF NOT EXISTS idx_prediction_history_user_id ON public.prediction_history(user_id);
CREATE INDEX IF NOT EXISTS idx_prediction_history_created_at ON public.prediction_history(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_experiment_history_user_id ON public.experiment_history(user_id);
CREATE INDEX IF NOT EXISTS idx_experiment_history_kernel ON public.experiment_history(kernel);
CREATE INDEX IF NOT EXISTS idx_experiment_history_created_at ON public.experiment_history(created_at DESC);

-- 9. HELPER FUNCTIONS
-- Check if current authenticated user is ADMIN
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'ADMIN'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger automatically creating profile on new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, full_name, role)
    VALUES (
        new.id,
        new.email,
        COALESCE(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
        COALESCE((new.raw_user_meta_data->>'role')::user_role, 'USER'::user_role)
    );
    
    INSERT INTO public.user_preferences (user_id)
    VALUES (new.id);

    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger binding
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 10. ROW LEVEL SECURITY (RLS) POLICIES

-- Bật RLS trên toàn bộ các bảng
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prediction_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.experiment_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_content ENABLE ROW LEVEL SECURITY;

-- 10.1 PROFILES POLICIES
CREATE POLICY "Users can view their own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = id OR public.is_admin());

CREATE POLICY "Users can update their own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id);

-- 10.2 USER PREFERENCES POLICIES
CREATE POLICY "Users can view and edit own preferences"
    ON public.user_preferences FOR ALL
    USING (auth.uid() = user_id OR public.is_admin())
    WITH CHECK (auth.uid() = user_id);

-- 10.3 PREDICTION HISTORY POLICIES
CREATE POLICY "Users can view their own prediction history"
    ON public.prediction_history FOR SELECT
    USING (auth.uid() = user_id OR public.is_admin());

CREATE POLICY "Users can insert their own predictions"
    ON public.prediction_history FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own predictions"
    ON public.prediction_history FOR DELETE
    USING (auth.uid() = user_id OR public.is_admin());

-- 10.4 EXPERIMENT HISTORY POLICIES
CREATE POLICY "Users can view their own experiments, Admin can view all"
    ON public.experiment_history FOR SELECT
    USING (auth.uid() = user_id OR public.is_admin());

CREATE POLICY "Users can insert their own experiments"
    ON public.experiment_history FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own experiments"
    ON public.experiment_history FOR DELETE
    USING (auth.uid() = user_id OR public.is_admin());

-- 10.5 APP CONTENT POLICIES
CREATE POLICY "Anyone can view app content"
    ON public.app_content FOR SELECT
    USING (true);

CREATE POLICY "Only Admin can update app content"
    ON public.app_content FOR ALL
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- 11. INITIAL SEED DATA FOR APP CONTENT
INSERT INTO public.app_content (key, title, content)
VALUES 
(
    'about_app',
    'Giới thiệu hệ thống Iris SVM',
    'Website phân loại hoa Iris bằng mô hình SVM (Support Vector Machine) chuyên sâu. Hệ thống cung cấp khả năng tự động nhận diện 4 đặc trưng, trực quan hóa ranh giới quyết định (Decision Boundary), huấn luyện đa Kernel (Linear, RBF, Poly, Sigmoid, Precomputed), lưu trữ thí nghiệm và so sánh Benchmark hiệu năng thuật toán.'
)
ON CONFLICT (key) DO NOTHING;

-- 12. HƯỚNG DẪN TẠO TÀI KHOẢN ADMIN:
-- Cách 1: Đăng ký tài khoản bình thường trong App, sau đó vào SQL Editor chạy lệnh:
-- UPDATE public.profiles SET role = 'ADMIN' WHERE email = 'your-email@example.com';
